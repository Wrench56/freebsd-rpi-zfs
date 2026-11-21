# FreeBSD ZFS on Raspberry Pi Zero W2

## Build

```sh
podman build --no-hosts --network=host -t image-builder .
mkdir out cache
podman run --rm --network=host -v $PWD/out:/out -v $PWD/cache:/cache image-builder
dd if=out/zero2w.img of=/dev/da0 bs=1m
```
