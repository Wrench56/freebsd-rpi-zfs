# FreeBSD ZFS on Raspberry Pi Zero W2

## Build

```sh
podman build --no-hosts --network=host -t image-builder .
mkdir out
podman run --rm -v $PWD/out:/out image-builder
dd if=out/zero2w.img of=/dev/da0 bs=1m
```
