# storage/uwal — Write-Ahead Log

> Durability primitive for Sagar and uFS.

Implements: sequential log append, fsync semantics, log replay on recovery,
log rotation, checkpoint triggering.

Part of the `storage/` category in Tattva OS.
