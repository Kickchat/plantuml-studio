#!/usr/bin/env python3
"""Public stable feed and immutable archive URLs for GitHub Releases."""
import os
import re


def urls(repository, tag):
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository):
        raise ValueError('Invalid GitHub repository')
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise ValueError('Stable release tag required')
    base = 'https://github.com/' + repository + '/releases/'
    return base + 'latest/download/appcast.xml', base + 'download/' + tag + '/'


if __name__ == '__main__':
    feed, archives = urls(os.environ['GITHUB_REPOSITORY'], os.environ['RELEASE_TAG'])
    print(feed)
    print(archives)
