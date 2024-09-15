import argparse
import dotenv
from git import Repo
from natsort import natsorted
import os
import json
import requests
import sys


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="wc/sync-versions.py",
        description="Synchronize App versions and architectures to WooCommerce",
    )
    parser.add_argument("--app", required=True)
    parser.add_argument("--base-url", required=False, default="staging.flecs.tech")
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


def versions_and_archs_from_repo(app):
    archs = set()
    versions = set()
    version_arch_matrix = set()
    try:
        repo = Repo(app)
        for tag in repo.tags:
            platforms = tag.repo.tree()["docker/Docker.platforms"]
            line = platforms.data_stream.read().decode().rstrip()
            for arch in line.split(","):
                archs.add(docker_to_arch(arch))
            versions.add(tag.name)
            version_arch_matrix.add("{}:{}".format(tag, ",".join(sorted(archs))))
    except Exception:
        print("Could not determine versions and archs for {}".format(app))
        None

    return [sorted(archs), natsorted(versions), natsorted(version_arch_matrix)]


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


def patch_attributes(attributes, archs, versions):
    keys = ["archs", "versions"]
    ids = [4, 0]  # 4 is the ID of the global "archs" enum
    values = [archs, versions]
    assert len(keys) == len(ids) == len(values)  # bug check...

    for i in range(len(keys)):
        try:
            # Update attribute if it already exists
            elem = next(filter(lambda attr: attr["name"] == keys[i], attributes))
            elem["id"] = ids[i]
            elem["options"] = values[i]
        except StopIteration:
            # Insert otherwise
            attributes = insert_attribute(attributes, keys[i], ids[i], values[i])

    return attributes


def build_meta_data(version_arch_matrix):
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
    print("Parsing versions and architectures from Git repository...")
    archs, versions, version_arch_matrix = versions_and_archs_from_repo(args.app)
    if len(archs) == 0:
        print("Found no architectures for App {}".format(args.app), file=sys.stderr)
        exit(1)
    if len(versions) == 0:
        print("Found no versions for App {}".format(args.app), file=sys.stderr)
        exit(1)
    assert len(versions) == len(version_arch_matrix)  # bug check...

    print("archs:\n\t{}".format("\n\t".join(archs)))
    print("versions:\n\t{}".format("\n\t".join(versions)))
    print("matrix:\n\t{}".format("\n\t".join(version_arch_matrix)))

    # Find all Apps with matching reverse domain name in WooCommerce. NOTE: There could
    # be multiple Apps, as some Apps might be released in white-labeled stores w/different
    # metadata, but identical App image
    print("Matching WooCommerce products with reverse-domain-name")
    apps = list(
        filter(
            lambda app: match_reverse_domain_name(app, args.app), wc_apps(args.base_url)
        )
    )
    if len(apps) == 0:
        print("Found no product matching App {}".format(args.app))
        exit(1)

    print("ids:\n\t{}".format("\n\t".join(str(app["id"]) for app in apps)))

    # Apply changes to all found Apps
    # TODO: Should we really auto-update in white-labeled stores?
    for app in apps:
        product_id = app["id"]
        app["attributes"] = patch_attributes(app["attributes"], archs, versions)
        meta_data = build_meta_data(version_arch_matrix)
        put_json = {"attributes": app["attributes"], "meta_data": meta_data}

        url = "https://{base_url}/wp-json/wc/v3/products/{id}".format(
            base_url=args.base_url, id=product_id
        )
        print("Updating product {id} @{url}".format(id=product_id, url=url))
        print(json.dumps(put_json, indent=2))
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


if __name__ == "__main__":
    main(sys.argv[1:])
