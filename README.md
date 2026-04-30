# Anodyne-chrp

AnodyneWiki's aggregator scripts.

### Usage

```shell
# enter frontend directory
cd /usr/src/anodyne-frontend

# setup ref icons etc
ruby /usr/src/chrp/chrp.rb --mode=init

# manually clear substance cache
ruby /usr/src/chrp/chrp.rb --cache=/tmp/chrp --mode=uncache EPT

# aggregate substance data without clearing cache
ruby /usr/src/chrp/chrp.rb --cache=/tmp/chrp --mode=search EPT

# aggregate substance data after clearing cache
ruby /usr/src/chrp/chrp.rb --cache=/tmp/chrp --mode=research EPT

# update substituent index
ruby /usr/src/chrp/chrp.rb --cache=/tmp/chrp --mode=index Phenethylamine
```
