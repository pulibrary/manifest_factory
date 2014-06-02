PUL Manifest Factory
====================

Build [IIIF Manifests](http://iiif.io/api/presentation/2.0/) from PUL-style METS.

Usage
-----

```bash
$ bin/build.sh sample_data/3103164.mets
```

Debugging
---------

Set `$doc-path` (line 9 or 10 in `lib/to_manifest.xql`) to point to a METS, and, if you're using sublime you can create a [custom build system](http://sublimetext.info/docs/en/reference/build_systems.html) with, e.g.:

```json
{
  "cmd": ["/home/jstroop/workspace/pul_manifest_factory/bin/build.sh"]
}
```
