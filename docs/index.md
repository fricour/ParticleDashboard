---
theme: dashboard
sql: 
  particle: ./.observablehq/cache/LPM_data.parquet
  ost: ./.observablehq/cache/optical_sediment_trap.parquet
  pss: ./.observablehq/cache/size_spectra.parquet
---

# Particles data from Biogeochemical-Argo floats

## Data from [Argo GDAC](http://www.argodatamgt.org/Access-to-data/Argo-GDAC-ftp-https-and-s3-servers)

```js
//
// Load data snapshots (big datasets are loaded with SQL (and duckDB behind the scenes, see the specifications at the top of the file))
//

// changed my mind with this resource https://observablehq.com/framework/sql for the big dataset (not the trajectory one for the leaflet map)
// Particle data
//const argo = FileAttachment("LPM_data.parquet").parquet();

// Trajectory data
const traj_argo = FileAttachment("trajectory_data.csv").csv({typed: true});

// Size spectra data
//const size_spectra = FileAttachment("size_spectra.parquet").parquet();

// OST data
//const ost_data = FileAttachment("optical_sediment_trap.parquet").parquet();
```

```js
// declaration of key variables

// particle size classes
const lpm_classes = [50.8, 64, 80.6, 102, 128, 161, 203, 256, 323, 406, 512, 645, 813, 1020, 1290, 1630, 2050, 2580]

// wmos (unique id for BGC-Argo floats)
const wmo = [1902578, 1902593, 1902601, 1902637, 1902685, 2903783, 2903787, 2903794, 3902471, 3902498, 4903634, 4903657, 4903658, 4903660, 4903739, 4903740, 5906970, 6904240, 6904241, 6990503, 6990514, 7901028]

// parking depths
const park_depths = [200, 500, 1000]

// Define a custom color palette (colorblind-friendly)
const colorPalette = [
  "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
  "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf"
];
```

```js
//
// input declarations
//
// define user inputs
const pickSizeClass = view(
  Inputs.select(
    lpm_classes,
    {
      multiple: false,
      label: "Pick a size class:",
      unique: true,
      sort: false,
      value: 102
    }
  )
);

const pickDepth = view(
  Inputs.checkbox(
    park_depths,
    {
      multiple: true,
      label: "Pick a depth:",
      unique: true,
      sort: false,
      value: [200]
    }
  )
)

const pickFloat = view(
  Inputs.select(
   wmo,
    {
      multiple: 5,
      label: "Pick a float:",
      unique: true,
      sort: false,
      value: [1902578]
    }
  )
);
```

```js
// switched to this because the sql query
//SELECT park_depth, wmo, size, concentration, juld
//FROM particle
//WHERE size = ${pickSizeClass}
//  AND park_depth = ${pickDepth}
//  AND wmo IN (${pickFloat})
// does not work with the IN operator
const particle_filtered = await sql([`SELECT * park_depth, WMO, size, concentration, juld 
                                      FROM particle 
                                      WHERE park_depth IN (${[pickDepth]}) 
                                      AND size IN (${[pickSizeClass]}) 
                                      AND wmo IN (${[pickFloat]})`])

const ost_filtered = await sql([`SELECT * 
                                 FROM ost 
                                 WHERE park_depth IN (${[pickDepth]}) 
                                 AND wmo IN (${[pickFloat]})`])    
                                 
const pss_filtered = await sql([`SELECT *
                                 FROM pss
                                 WHERE park_depth IN (${[pickDepth]}) 
                                 AND wmo IN (${[pickFloat]})`])
```

```js
// Create a color scale based on unique WMO values
const colorScale = d3.scaleOrdinal()
  .domain(wmo)
  .range(colorPalette);
```

```js
// leaflet map to plot floats' trajectories
// made with Claude Ai
const div = display(document.createElement("div"));
div.style = "height: 400px;";

const map = L.map(div)
  .setView([0, 180], 2); // centered on Greenwich, zoom level 2

L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
  maxZoom: 19, 
  attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
})
  .addTo(map);

const groupedData = d3.group(traj_argo, d => d.wmo);

// Prepare an array to hold all polylines
let allPolylines = [];

// For each float (WMO)
groupedData.forEach((floatData, wmo) => {
  // Sort the data by cycle to ensure correct trajectory
  floatData.sort((a, b) => a.cycle - b.cycle);
  
  // Extract coordinates
  const latlngs = floatData.map(d => [d.latitude, d.longitude]);
  
  // Create a polyline for the trajectory
  const polyline = L.polyline(latlngs, {
    color: colorScale(wmo),
    weight: 5,
    opacity: 0.7
  }).addTo(map);
  
  // Add to our array of all polylines
  allPolylines.push(polyline);
  
  // Add a marker for the start point
  L.circleMarker(latlngs[latlngs.length - 1], {
    color: colorScale(wmo),
    fillColor: "black",
    fillOpacity: 0.5,
    radius: 5
  }).addTo(map)
    .bindPopup(`Float: ${wmo}<br>Last update on ${floatData[floatData.length - 1].date}`);
});

// Create a feature group from all polylines
const group = L.featureGroup(allPolylines);
```

```js
// Create the particle plot (when floats have reached their parking depth)
const particle_plot = Plot.plot({
  marks: [
    Plot.dot(particle_filtered, {
      y: "concentration",
      x: "juld",
      fill: d => colorScale(d.wmo),  // Use the custom color scale
      r: 3
    }),
    Plot.tip(particle_filtered, Plot.pointer({
      y: "concentration",
      x: "juld",
      title: d => `WMO: ${d.wmo}\nDate: ${d.juld}\nConcentration: ${d.concentration.toFixed(2)}`
    }))
  ],
  y: {
    label: "Concentration (#/L)",
    reverse: false
  },
  x: {
    label: "Date",
    //tickFormat: "%b %Y"  // Format x-axis ticks as month and year
  },
  width: 800,  // Increased width for better visibility
  height: 500,  // Increased height for better visibility
  style: {
    fontFamily: "sans-serif",
    fontSize: 12
  },
  marginRight: 100  // Add right margin for the legend
})
```

```js
// Particle size spectra plot
const pss_plot = Plot.plot({
  marks: [
    Plot.dot(pss_filtered, {
      y: "mean_slope",
      x: "date",
      fill: d => colorScale(d.wmo),  // Use the custom color scale
      r: 3
    }),
    Plot.tip(pss_filtered, Plot.pointer({
      y: "mean_slope",
      x: "date",
      title: d => `WMO: ${d.wmo}\nDate: ${d.date}\nMean slope: ${d.mean_slope.toFixed(2)}`
    }))
  ],
  y: {
    label: "Mean slope",
    reverse: false
  },
  x: {
    label: "Date",
    //tickFormat: "%b %Y"  // Format x-axis ticks as month and year
  },
  width: 800,  // Increased width for better visibility
  height: 500,  // Increased height for better visibility
  style: {
    fontFamily: "sans-serif",
    fontSize: 12
  },
  marginRight: 100  // Add right margin for the legend
})
```

```js
// Optical sediment trap plot
const ost_plot = Plot.plot({
  marks: [
    Plot.dot(ost_filtered, {
      y: "small_flux",
      x: "max_time",
      fill: d => colorScale(d.wmo),  // Use the custom color scale
      r: 3
    }),
    Plot.tip(ost_filtered, Plot.pointer({
      y: "small_flux",
      x: "max_time",
      title: d => `WMO: ${d.wmo}\nDate: ${d.max_time}\nSmall flux: ${d.small_flux.toFixed(2)}`
    }))
  ],
  y: {
    label: "Small particle flux",
    reverse: false
  },
  x: {
    label: "Date",
    //tickFormat: "%b %Y"  // Format x-axis ticks as month and year
  },
  width: 800,  // Increased width for better visibility
  height: 500,  // Increased height for better visibility
  style: {
    fontFamily: "sans-serif",
    fontSize: 12
  },
  marginRight: 100  // Add right margin for the legend
})
```

```js
// create input
const pointMax = Inputs.range([0, 10], {step: 1, value: 10, width: 60});
```

<div class="grid grid-cols-4">
  <div class="card grid-colspan-2 grid-rowspan-1" style="padding: 0px;">
    <div style="padding: 1rem;">
      <h2><strong>Floats trajectories</strong></h2>
      <h3>Black markers show the last file update</h3>
      ${div}
    </div>
  </div>
  <div class="card grid-colspan-2 grid-rowspan-1">
    <h2><strong>Particle size spectra</strong></h2>
    <h3>Mean slope of particle size spectra</h3>
    ${pss_plot}
</div>

<div class="card grid-colspan-2 grid-rowspan-1">
  <h2><strong>Particle concentrations</strong></h2>
  <h3>Filter points out by decreasing the maximum concentration value</h3>
  <div style="display: flex; flex-direction: column; align-items: center;">
    <div>${pointMax}</div>
  </div>
  ${particle_plot}
</div>

<div class="card grid-colspan-2 grid-rowspan-1">
  <h2><strong>Optical sediment trap</strong></h2>
  <h3>Small particle flux</h3>
  ${ost_plot}
</div>