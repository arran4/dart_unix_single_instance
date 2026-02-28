# Agent Instructions

## Diagram Generation

The program flow diagram located at `assets/flow.svg` is generated from the Mermaid definition file `flow.mmd`.

When making changes to the program flow or the diagram:
1. First edit the source definition in `flow.mmd`.
2. Generate the updated SVG using Mermaid CLI (`@mermaid-js/mermaid-cli`).

Run the following command to update the SVG:

```bash
mmdc -i flow.mmd -o assets/flow.svg
```
