# FPGA Repository
## 1.Introduction
This Repository is built strictly for educational purpose, focuses on FPGA-based logic design and development workflow practice
## 2.Project Structure
Here is an overview of the repository folders and their contents:
### 📁 `/src`
- **Description**: Source files
- **Contents**: Contains all Verilog/VHDL design files (`.v`, `.vhd`). This is the core logic of the project.

### 📁 `/ip`
- **Description**: IP Cores
- **Contents**: Configuration files and tcl scripts for Vivado IP cores (e.g., Clock Wizard, FIFO, etc.).

### 📁 `/sim`
- **Description**: Simulation Files
- **Contents**: Testbench files (`.tv`, `.v`) used for verifying the design logic.

### 📁 `/constr`
- **Description**: Constraints
- **Contents**: XDC files defining pin assignments and timing constraints.

### 📁 `/hw`
- **Description**: Hardware Module
- **Contents**: 
  - Schematics and hardware connections.
  - Pin definitions for WS and L/R ports.
  - FPGA development board specifications.

### 📁 `/docs`
- **Description**: Documentation
- **Contents**: Detailed documentation, design specifications, and data format references (e.g., Q1.10 format, normalization rules).
