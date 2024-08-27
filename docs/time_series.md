---
sql:
  taxo: ./.observablehq/cache/taxo_data.parquet
---

```js
const taxo_data = FileAttachment("taxo_data.parquet").parquet();

display(Inputs.table(taxo_data));
```

```js
const taxo_filtered = await sql([`SELECT *  
                                  FROM taxo`])
```

```js
// Create a continuous color scale
const colorScale = d3.scaleSequential(d3.interpolateViridis)
  .domain([0, 100]);  // Adjust this domain to match your data range

```

```js
const taxo_plot = Plot.plot({
  marks: [
    Plot.dot(taxo_filtered, {
      y: "depth",
      x: "juld",
      stroke: "concentration_total",
      r: 1,
      opacity: 0.5,
    }),
    Plot.tip(taxo_filtered, Plot.pointer({
      y: "depth",
      x: "juld",
      title: d => `WMO: ${d.wmo}`
    })),
    Plot.crosshair(taxo_filtered, {x: "juld", y: "depth"})
  ],
  color: {
    type: "sequential",
    scheme: "viridis",  // You can also use "plasma", "inferno", or "magma"
    legend: true
  },
  style: {
    background: "black",
    color: "white"  // Text color
  },
  y: {
    label: "Depth (m)",  // Changed from "Concentration (#/L)" to "Depth (m)"
    reverse: true
  },
  x: {
    label: "Date"
  },
  width: 800,
  height: 500,
  style: {
    fontFamily: "sans-serif",
    fontSize: 12
  },
  marginRight: 100
});
```

${taxo_plot}