# Anodyne-chrp

AnodyneWiki's aggregator scripts.

## Usage
### with nix
`nix develop .`

### without nix

```shell
# enter frontend directory, or pass --frontend=/usr/src/anodyne-frontend to each command
cd /usr/src/anodyne-frontend

# the database defaults to db.sqlite in the frontend directory, override with --database=PATH

# setup ref icons etc
/usr/src/chrp/exe/chrp --mode=init

# manually clear substance cache
/usr/src/chrp/exe/chrp --cache=/tmp/chrp --mode=uncache EPT

# aggregate substance data without clearing cache
/usr/src/chrp/exe/chrp --cache=/tmp/chrp --mode=search EPT

# aggregate substance data after clearing cache
/usr/src/chrp/exe/chrp --cache=/tmp/chrp --mode=research EPT

# update a class index (class/ or substituted/)
/usr/src/chrp/exe/chrp --mode=index Phenethylamine

# update the class indexes a substance belongs to
/usr/src/chrp/exe/chrp --mode=index Magnesium

# update every class index
/usr/src/chrp/exe/chrp --mode=index

# leave out sources that are offline
/usr/src/chrp/exe/chrp --cache=/tmp/chrp --mode=search --skip=dbi-igs,protestkit EPT
```
