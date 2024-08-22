---
theme: dashboard
---

# Particles data from Biogeochemical-Argo floats

## Data from [Argo GDAC](http://www.argodatamgt.org/Access-to-data/Argo-GDAC-ftp-https-and-s3-servers)

```js
// import leaftlet library (note, it is imported implicitly in the Observable framework), see https://observablehq.com/framework/lib/leaflet
import * as L from "npm:leaflet";
```

```js
//
// Load data snapshots
//

// Particle data
const argo = FileAttachment("LPM_data.csv").csv({typed: true});

// Trajectory data
const traj_argo = FileAttachment("trajectory_data.csv").csv({typed: true});

// Size spectra data
const size_spectra = FileAttachment("size_spectra.csv").csv({typed: true});

// OST data
const ost_data = FileAttachment("optical_sediment_trap.csv").csv({typed: true});
```

```js
```

```js
// define user inputs
const pickSizeClass = view(
  Inputs.select(
    argo.map((d) => d.size),
    {
      multiple: false,
      label: "Pick a size class:",
      unique: true,
      sort: false,
      value: "NP_Size_50.8"
    }
  )
);

const pickDepth = view(
  Inputs.select(
    argo.map((d) => d.park_depth),
    {
      multiple: false,
      label: "Pick a depth:",
      unique: true,
      sort: false,
      value: "1000 m"
    }
  )
);

const pickFloat = view(
  Inputs.select(
    argo.map((d) => d.wmo),
    {
      multiple: true,
      label: "Pick a float:",
      unique: true,
      sort: false,
      value: "6904240"
    }
  )
);
```

```js
// filter data based on user input
const argo_filtered = argo.filter(d => 
  pickSizeClass.includes(d.size) && 
  pickDepth.includes(d.park_depth) &&
  pickFloat.includes(d.wmo)
);   

// filter particle size spectra
const pss_filtered = size_spectra.filter(d => 
  pickDepth.includes(d.park_depth) &&
  pickFloat.includes(d.wmo)
);   

// filter optical sediment trap data
const ost_filtered = ost_data.filter(d => 
  pickDepth.includes(d.park_depth) &&
  pickFloat.includes(d.wmo)
);   
```

```js
// Define a custom color palette (colorblind-friendly)
const colorPalette = [
  "#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd",
  "#8c564b", "#e377c2", "#7f7f7f", "#bcbd22", "#17becf"
];

// Create a color scale based on unique WMO values
const wmoValues = [...new Set(argo.map(d => d.wmo))];
const colorScale = d3.scaleOrdinal()
  .domain(wmoValues)
  .range(colorPalette);
```

```js
// show table
//Inputs.table(argo_filtered)
//Inputs.table(size_spectra)
Inputs.table(ost_data)
```

```js
// leaflet map to plot floats' trajectories
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
    Plot.dot(argo_filtered, {
      y: "concentration",
      x: "juld",
      fill: d => colorScale(d.wmo),  // Use the custom color scale
      r: 3
    }),
    Plot.tip(argo_filtered, Plot.pointer({
      y: "concentration",
      x: "juld",
      title: d => `WMO: ${d.wmo}\nDepth: ${d.depth.toFixed(1)} m\nDate: ${d.juld}\nConcentration: ${d.concentration.toFixed(2)}`
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
  //color: {
  //  legend: true,  // Add a color legend
  //  label: "WMO"
  //},
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
      title: d => `WMO: ${d.wmo}\nDate: ${d.date}}`
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
  //color: {
  //  legend: true,  // Add a color legend
  //  label: "WMO"
  //},
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
      title: d => `WMO: ${d.wmo}\nDate: ${d.max_time}\nSmall flux: ${d.small_flux}`
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
  //color: {
  //  legend: true,  // Add a color legend
  //  label: "WMO"
  //},
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
// taken from https://raw.githubusercontent.com/observablehq/framework/main/examples/eia/src/index.md
function centerResize(render) {
  const div = resize(render);
  div.style.display = "flex";
  div.style.flexDirection = "column";
  div.style.alignItems = "center";
  return div;
}
```

```js
//
// Big thanks to ClaudeAI ...
//
// get max concentration value for the filtered argo dataframe
const concentrations = argo_filtered.map(row => parseFloat(row.concentration));
// Calculate max
const maxConcentration = Math.max(...concentrations);

// Calculate mean
const sumConcentration = concentrations.reduce((sum, value) => sum + value, 0);
const meanConcentration = sumConcentration / concentrations.length;

// Calculate median
const sortedConcentrations = [...concentrations].sort((a, b) => a - b);
const midpoint = Math.floor(sortedConcentrations.length / 2);
const medianConcentration = 
  sortedConcentrations.length % 2 !== 0
    ? sortedConcentrations[midpoint]
    : (sortedConcentrations[midpoint - 1] + sortedConcentrations[midpoint]) / 2;

// Round values if needed
const roundToDecimalPlaces = (value, places) => Number(value.toFixed(places));

const roundedMean = roundToDecimalPlaces(meanConcentration, 2);
const roundedMedian = roundToDecimalPlaces(medianConcentration, 2);

// create input
const pointMax = Inputs.range([0, maxConcentration], {step: 1, value: maxConcentration, width: 60});
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