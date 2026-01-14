curl https://downloader.hytale.com/hytale-downloader.zip --output download.zip
unzip download.zip -d out
nix hash path out > hash.nix
rm download.zip
rm -r out
