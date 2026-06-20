# Thin wrapper around snapraid-btrfs that refuses an *unscoped* `fix`.
#
# A bare `snapraid-btrfs fix` (no -d/--filter-disk, -e or -f) tells SnapRAID to
# revert every data disk to the last sync using the LIVE filesystem, which
# overwrites anything changed since then. Scoped fixes read the other disks
# from their read-only snapshots and are the intended recovery path, so those
# pass through untouched. Set SNAPRAID_BTRFS_ALLOW_BARE_FIX=1 to override.
{
  writeShellApplication,
  snapraid-btrfs-unwrapped,
}:
writeShellApplication {
  name = "snapraid-btrfs";
  text = ''
    real="${snapraid-btrfs-unwrapped}/bin/snapraid-btrfs"

    is_fix=0
    has_scope=0
    for arg in "$@"; do
      case "$arg" in
        fix)
          is_fix=1
          ;;
        -d | --filter-disk | --filter-disk=* | -e | -f | --filter | --filter=*)
          has_scope=1
          ;;
        --*)
          : # long options other than the ones above never scope a fix
          ;;
        -[A-Za-z]*)
          # short-option cluster: treat -d/-e/-f (alone or combined) as scoping
          if [[ "$arg" =~ ^-[A-Za-z]*[def] ]]; then
            has_scope=1
          fi
          ;;
      esac
    done

    if [[ "$is_fix" -eq 1 && "$has_scope" -eq 0 && "''${SNAPRAID_BTRFS_ALLOW_BARE_FIX:-0}" != 1 ]]; then
      printf '%s\n' \
        'snapraid-btrfs: refusing to run an unscoped "fix".' \
        "" \
        'A bare "fix" reverts every data disk to the last sync using the LIVE' \
        'filesystem, overwriting anything changed since then. This guard blocks it.' \
        "" \
        'Instead:' \
        '  * Recover accidental deletes/edits straight from the snapshot:' \
        '      cp -a /mnt/diskN/.snapshots/<synced#>/snapshot/<path> /mnt/diskN/<path>' \
        '  * Repair a real disk failure, scoped to one disk:' \
        '      snapraid-btrfs --interactive fix -d <disk>' \
        '  * Fix only blocks flagged by scrub/sync:' \
        '      snapraid-btrfs --interactive fix -e' \
        "" \
        'To override intentionally (you understand the risk):' \
        '  SNAPRAID_BTRFS_ALLOW_BARE_FIX=1 snapraid-btrfs fix ...' >&2
      exit 64
    fi

    exec "$real" "$@"
  '';
}
