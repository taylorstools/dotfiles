# Placeholder. install.sh generates the real hostId and postinstall.sh syncs it
# over this file; the ZFS pool will only import on a system whose hostId matches
# the one in effect when the pool was created.
{ networking.hostId = "00000000"; }
