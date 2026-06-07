"""Git Sync — pull main from GitHub into /config on the HA host.

Exposes one service, ``git_sync.pull``, that fetches the origin/main
commit and hard-resets /config to it. The GitHub Actions deploy
workflow calls this service after each merge so new commits land on
the HA host without depending on the SSH addon's stdin support
(removed for core_ssh) or the git binary (no longer shipped in the
HA Core container image).

Implemented with dulwich (pure-Python git). Uses the low-level
``client.fetch`` + targeted ref writes rather than ``porcelain.fetch``
so it does NOT try to mirror every remote ref locally. The backup
automation pushes branches like ``ha-backup/<date>`` that can leave
``refs/remotes/origin/`` in a state where a regular file and a
directory want to live at the same path; ``porcelain.fetch`` cannot
write through that, but we don't need to — the deploy only cares
about main.
"""
from __future__ import annotations

import logging

from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers.typing import ConfigType

_LOGGER = logging.getLogger(__name__)

DOMAIN = "git_sync"
CONFIG_DIR = "/config"
REMOTE = "origin"
BRANCH = "main"

CONFIG_SCHEMA = cv.empty_config_schema(DOMAIN)


async def async_setup(hass: HomeAssistant, config: ConfigType) -> bool:
    """Register the git_sync.pull service."""

    async def handle_pull(_: ServiceCall) -> None:
        await hass.async_add_executor_job(_fast_forward_to_origin_main)

    hass.services.async_register(DOMAIN, "pull", handle_pull)
    return True


def _fast_forward_to_origin_main() -> None:
    """Fetch the latest main from origin and hard-reset /config to it.

    Uses dulwich's low-level ``client.fetch`` with a ``determine_wants``
    callback that asks for exactly one ref. ``refs/remotes/origin/main``
    is deliberately NOT updated: see the module docstring for why.
    Only ``refs/heads/main`` and ``HEAD`` get touched.
    """
    from dulwich import porcelain
    from dulwich.client import get_transport_and_path
    from dulwich.repo import Repo

    repo = Repo(CONFIG_DIR)
    config = repo.get_config()
    url = config.get((b"remote", REMOTE.encode()), b"url")
    if isinstance(url, bytes):
        url = url.decode()

    client, path = get_transport_and_path(url)
    wanted_ref = f"refs/heads/{BRANCH}".encode()

    def determine_wants(remote_refs, **_kwargs):
        if wanted_ref not in remote_refs:
            raise RuntimeError(
                f"Remote {REMOTE!r} does not advertise {wanted_ref.decode()!r}"
            )
        return [remote_refs[wanted_ref]]

    fetch_result = client.fetch(path, repo, determine_wants=determine_wants)
    target_sha = fetch_result.refs[wanted_ref]

    local_ref = f"refs/heads/{BRANCH}".encode()
    repo.refs[local_ref] = target_sha
    repo.refs.set_symbolic_ref(b"HEAD", local_ref)
    porcelain.reset(repo, "hard", target_sha)

    _LOGGER.info(
        "git_sync.pull synced /config to %s/%s @ %s",
        REMOTE,
        BRANCH,
        target_sha.decode()[:7],
    )
