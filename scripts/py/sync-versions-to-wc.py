import argparse
import dotenv
from git import Repo, TagReference
from natsort import natsorted
import os
import json
import re
import requests
import sys

class AppRelease:
    def __init__(self):
        self.versions = set()
        self.archs = set()
        self.version_arch_matrix = set()

def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="wc/sync-versions.py",
        description="Synchronize App versions and architectures to WooCommerce",
    )
    parser.add_argument("--app", required=True)
    parser.add_argument("--app-version", required=False, default="")
    parser.add_argument("--base-url", required=False, default="staging.flecs.tech")
    parser.add_argument("--allow-no-product", required=False, action='store_true')
    parser.add_argument("--dry-run", required=False, action='store_true')
    args = parser.parse_args(argv)
    if args.app[-1] == "/":
        args.app = args.app[:-1]
    return args


def docker_to_arch(arch):
    if arch == "linux/amd64":
        return "amd64"
    if arch == "linux/arm64":
        return "arm64"
    if arch == "linux/arm/v7":
        return "armhf"
    raise ValueError("Invalid value {} for arch".format(arch))


def variants_from_tag(tag: TagReference):
    variants = set()
    pattern = r"manifest\.?(.*)\.json"
    for file in tag.repo.tree().blobs:
        match = re.search(pattern, file.name)
        if match:
            variants.add(match.group(1))
    return variants


def releases_from_tags(tags):
    releases = dict()
    for tag in tags:
        print("Processing tag {}".format(tag))
        variants = variants_from_tag(tag)

        for variant in variants:
            release = releases.setdefault(variant, AppRelease())
            release.versions.add(tag.name)
            try:
                platforms = tag.repo.tree()["docker/Docker.{}.platforms".format(variant)]
            except:
                platforms = tag.repo.tree()["docker/Docker.platforms".format(variant)]
            line = platforms.data_stream.read().decode().rstrip()
            print("Processing line {}".format(line))
            line = ''.join(line.split())
            for raw_arch in line.split(","):
                release.archs.add(docker_to_arch(raw_arch))
            release.version_arch_matrix.add("{}:{}".format(tag, ",".join(sorted(release.archs))))
    return releases


def releases_from_repo(app):
    releases = dict()
    try:
        repo = Repo(app)
        releases = releases_from_tags(repo.tags)
    except Exception as e:
        print("Could not determine variants, versions and archs for {}: {}".format(app, e))
    return releases


def release_from_repo(app, tag_name):
    repo = Repo(app)
    for existing_tag in repo.tags:
        if existing_tag.name == tag_name:
            tag = existing_tag
            break
    else:
        raise Exception("Tag {tag_name} not found for app {app}".format(tag_name=tag_name, app=app))
    return releases_from_tags([tag])


def wc_apps(base_url):
    page = 1
    per_page = 25
    products = json.loads("[]")
    while True:
        # Extend empty JSON array of products by next page. WooCommerce uses pagination with max. 100 items per page.
        # Fetching 25 at a time seems reasonable right now, which takes ~5 calls to load all apps.
        products.extend(
            json.loads(
                requests.get(
                    "https://{base_url}/wp-json/wc/v3/products?category=27&per_page={per_page}&page={page}".format(
                        base_url=base_url, per_page=per_page, page=page
                    ),
                    headers={
                        "User-Agent": "curl/8.4.0"
                    },  # Why bother rejecting User-Agents when *this* works?
                    auth=(
                        os.environ.get("WC_CONSUMER_KEY"),
                        os.environ.get("WC_CONSUMER_SECRET"),
                    ),
                ).text
            )
        )
        # Fetching is done when less than per_page products have been fetched this time
        if len(products) != (page * per_page):
            break
        page = page + 1

    return products


def match_reverse_domain_name(wc_app, reverse_domain_name):
    try:
        elem = next(
            filter(
                lambda attr: attr["name"] == "reverse-domain-name", wc_app["attributes"]
            )
        )
        if reverse_domain_name in elem["options"]:
            return True
    except StopIteration:
        pass

    return False


# Attributes cannot be extended by POSTing additional data
# Instead, we have to append to the existing attributes and
# POST the whole blob
def insert_attribute(attributes, name, id, options):
    pos = len(attributes)
    attributes.append(
        {
            "id": id,
            "name": name,
            "slug": name,
            "position": pos,
            "visible": True,
            "variation": False,
            "options": options,
        }
    )
    return attributes


def patch_attributes(attributes, archs, versions, replace):
    keys = ["archs", "versions"]
    ids = [4, 0]  # 4 is the ID of the global "archs" enum
    values = [archs, versions]
    assert len(keys) == len(ids) == len(values)  # bug check...

    for i in range(len(keys)):
        try:
            # Update attribute if it already exists
            elem = next(filter(lambda attr: attr["name"] == keys[i], attributes))
            elem["id"] = ids[i]
            if replace:
                elem["options"] = values[i]
            else:
                # Create one collection of new and old values with unique values
                options = set(elem["options"] + values[i])
                # Create sorted list of set
                elem["options"] = natsorted(list(options))
        except StopIteration:
            # Insert otherwise
            attributes = insert_attribute(attributes, keys[i], ids[i], values[i])

    return attributes


def build_meta_data(version_arch_matrix):
    return [{"key": "flecs_version_arch_matrix", "value": version_arch_matrix}]

def get_version_arch_matrix(meta_data):
    try:
        return next(filter(lambda meta: meta["key"] == "flecs_version_arch_matrix", meta_data))["value"]
    except StopIteration:
        return []

def patch_meta_data(meta_data, new_version_arch_matrix, replace):
    if replace:
        version_arch_matrix = new_version_arch_matrix
    else:
        version_arch_matrix =  get_version_arch_matrix(meta_data)
        # Create one collection of new and old values with unique values
        version_arch_matrix = set(version_arch_matrix + new_version_arch_matrix)
        # Create sorted list of set
        version_arch_matrix = natsorted(list(version_arch_matrix))
    return [{"key": "flecs_version_arch_matrix", "value": version_arch_matrix}]

def main(argv):
    dotenv.load_dotenv()
    REQUIRED_ENV_VARS = ["WC_CONSUMER_KEY", "WC_CONSUMER_SECRET"]
    for env in REQUIRED_ENV_VARS:
        if not env in os.environ:
            print(
                "Environment variable WC_CONSUMER_KEY is required, but not set",
                file=sys.stderr,
            )
            exit(1)

    args = parse_args(argv)

    # We'll check the App repository for everything we need first, as it's much
    # faster than retrieving all Apps through the WooCommerce REST API
    print("Parsing variants, versions and architectures from Git repository...")
    no_products_found_counter = 0
    error_count = 0
    replace_attributes = True
    replace_meta_data = True
    if args.app_version == "":
        releases = releases_from_repo(args.app)
    else:
        releases = release_from_repo(args.app, args.app_version)
        replace_attributes = False
        replace_meta_data = False
    for variant, release in releases.items():
        release.archs = sorted(release.archs)
        release.versions = natsorted(release.versions)
        release.version_arch_matrix = natsorted(release.version_arch_matrix)
        print("variant {}:".format(variant))
        print("\tarchs:\n\t\t{}".format("\n\t\t".join(release.archs)))
        print("\tversions:\n\t\t{}".format("\n\t\t".join(release.versions)))
        print("\tmatrix:\n\t\t{}".format("\n\t\t".join(release.version_arch_matrix)))
    for variant, release in releases.items():
        assert len(release.versions) == len(release.version_arch_matrix)  # bug check...
        variant_name = args.app
        if variant != "":
            variant_name = "{}-{}".format(args.app, variant)

        if len(release.versions) == 0:
            print("Found no versions for App {}".format(variant_name), file=sys.stderr)
            continue
        if len(release.archs) == 0:
            print("Found no architectures for App {}".format(variant_name), file=sys.stderr)
            error_count += 1
            continue

        # Find all Apps with matching reverse domain name in WooCommerce. NOTE: There could
        # be multiple Apps, as some Apps might be released in white-labeled stores w/different
        # metadata, but identical App image
        print("Matching WooCommerce products with {}".format(variant_name))
        apps = list(
            filter(
                lambda app: match_reverse_domain_name(app, variant_name), wc_apps(args.base_url)
            )
        )
        if len(apps) == 0:
            print("Found no product matching App {}".format(variant_name))
            no_products_found_counter += 1
            continue

        print("ids:\n\t{}".format("\n\t".join(str(app["id"]) for app in apps)))

        # Apply changes to all found Apps
        # TODO: Should we really auto-update in white-labeled stores?
        for app in apps:
            product_id = app["id"]
            app["attributes"] = patch_attributes(app["attributes"], release.archs, release.versions, replace_attributes)
            meta_data = patch_meta_data(app["meta_data"], release.version_arch_matrix, replace_meta_data)
            put_json = {"attributes": app["attributes"], "meta_data": meta_data}

            url = "https://{base_url}/wp-json/wc/v3/products/{id}".format(
                base_url=args.base_url, id=product_id
            )
            print("Updating product {id} @{url}".format(id=product_id, url=url))
            print(json.dumps(put_json, indent=2))
            if args.dry_run:
                print("Skipped updating {id} @{url}, due to dry-run".format(id=product_id, url=url))
            else:
                update_product = requests.put(
                    url=url,
                    headers={"User-Agent": "curl/8.4.0", "Content-Type": "application/json"},
                    auth=(
                        os.environ.get("WC_CONSUMER_KEY"),
                        os.environ.get("WC_CONSUMER_SECRET"),
                    ),
                    data=json.dumps(put_json),
                )
                print(update_product)
    if no_products_found_counter > 0 and not args.allow_no_product:
        exit(no_products_found_counter + error_count)
    exit(error_count)


if __name__ == "__main__":
    main(sys.argv[1:])
