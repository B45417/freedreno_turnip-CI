This is a bash script to build freedreno/turnip for android as an adrenotool package.
  
### To Build Locally
- Obtain the script [turnip_builder.sh](https://raw.githubusercontent.com/Weab-chan/freedreno_turnip-CI/main/turnip_builder.sh). (visit the link and use ```CTRL + S``` keys)
- Prepare the environment :
    - sudo sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources
    - sudo apt update
    - sudo apt build-dep mesa -y
- Execute script on linux terminal ```bash ./turnip_builder.sh```

### References

- https://forum.xda-developers.com/t/getting-freedreno-turnip-mesa-vulkan-driver-on-a-poco-f3.4323871/
- https://github.com/ilhan-athn7/freedreno_turnip-CI
- https://gitlab.freedesktop.org/mesa/mesa/-/issues/6802
