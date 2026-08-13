`importer.sh` loses records at the window boundary. With `--batch-size` set above the
page limit, everything past the first page of each batch is dropped, and the process
still finishes with `exit 0` — so nothing downstream can tell a short load from a
complete one.

Related: #42.
