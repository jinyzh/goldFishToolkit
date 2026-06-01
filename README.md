# goldFishToolkit
A Cadence Virtuoso SKILL utility for IC layout


## Features

- Hierarchical device pin metal shapes/paths refill for EMX blackbox workflows
- Select off-grid objects
- Snap selected objects to grid
- Clear steiners
- Create stair line polygon
- Layout utility menu integration

## Installation

Add this line to `.cdsinit`:

```skill
load("/path/to/goldFishToolkit/goldFishToolkit.il")
```

Then open a layout window or run:

```skill
gfInstallMenu()
```


## Usage

Menu path:

Layout Editor -> goldFishToolkit
Warnings

Do not use geometry snap blindly on PDK device internals.

Pin refill generates top-level drawing shapes.

Always run DRC/LVS after layout modification.



## Tested Environment

- Cadence Virtuoso IC231
- Rocky Linux 8.10
