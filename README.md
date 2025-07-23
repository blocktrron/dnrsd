# Distributed Neighbor Report Synchronization Daemon

This project implements synchronization of neighbor reports between multiple OpenWrt access points. Neighbor reports are used in Wi-Fi networks to share information about neighboring access points, which can help devices make better roaming decisions, reduce off-channel time and thus improve user-experience.

## Features

 - Neighbor discovery by client beacon reports
 - Neighbor report synchronization through AP beacon frames
 - No backhaul connection required between APs
 - Written in ucode

## Comparison with DAWN / usteer

dnrsd is not a steering daemon like DAWN or usteer. While all of these projects share the goal of improving roaming, usteer and DAWN aim for active steering of clients between bands and / or access points.

The goal with dnrsd was to implement a simple solution for synchronizing neighbor reports without the need to use the IP network for communication between access points.

## Installation

At the moment dnrsd requires two patches to be applied to OpenWrt which can both be found in the `patches` directory.

After applying the patches to an OpenWrt main branch, you can build the package by adding this repository to your feeds:

```bash
cp feeds.conf.default feeds.conf
echo "src-git dnrsd https://github.com/blocktrron/dnrsd.git" >> feeds.conf
./scripts/feeds update dnrsd
./scripts/feeds install dnrsd
```

dnrsd can then be built as part of the OpenWrt build process.

## Usage

After installation, the dnrsd daemon is automatically started by the OpenWrt init system.
