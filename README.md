# .

🛡️ Image Duplicate Detection for Wildlife Conservation

This project implements a high-performance **Difference Hashing (dHash)** architecture in Verilog, designed for real-time **image duplicate detection** in wildlife camera traps. By generating compact 64-bit image signatures directly on FPGA, the system identifies and filters redundant frames before storage or transmission.

---

## 📖 Project Overview

In wildlife conservation, remote camera traps generate massive amounts of redundant image data due to repeated triggers, static backgrounds, and environmental noise.

### 🎯 Objective

Design a **real-time, synthesizable FPGA system** that:

* Processes (640 \times 480) grayscale images
* Detects visually similar (duplicate) frames
* Eliminates redundant data at the hardware level

👉 Result: Significant reduction in **storage, bandwidth, and power consumption**

---

## 🚀 Key Features

* **dHash Algorithm:** Robust to lighting changes (gradient-based comparison)
* **Real-Time Streaming Processing:** No full-frame buffering required
* **On-the-Fly Accumulation:** Memory-efficient downsampling
* **Duplicate Detection Logic:** Based on Hamming distance
* **Configurable Threshold:** Tunable similarity sensitivity (default = **10**)
* **FPGA Optimized:** Designed for **Digilent Basys 3 (Artix-7, XC7A35T)**

---

## 🏗️ System Architecture

The system follows a **fully streaming hardware pipeline**, optimized for FPGA constraints.

---

### 1️⃣ Stream-Based On-the-Fly Box Filtering (Core Innovation)

The OV7670 camera module outputs image data as a continuous **8-bit pixel stream**. Instead of storing the full (640 \times 480) frame, the system processes each pixel in real-time using an efficient streaming architecture.

#### 🔧 Region Mapping

* The image is divided into **72 regions (9 × 8 grid)**
* Each incoming pixel is mapped to a region based on its **(X, Y) position**

#### ⚙️ Accumulator + Counter Logic

Each region contains:

* **Accumulator register** → stores sum of pixel intensities
* **Counter register** → counts number of pixels

For every incoming pixel:

* Pixel value is **added to the corresponding accumulator**
* The region’s **counter is incremented simultaneously**

#### 📊 Spatial Averaging (Box Filter)

After processing the complete frame:

* Each accumulator is **divided by its corresponding count**
* This computes the **average intensity for each region**

#### ✅ Result

* Produces a downsampled **(9 \times 8)** image
* Each pixel represents the **average intensity of its corresponding spatial block**

> 💡 The OV7670 camera streams pixels one at a time, and each pixel is dynamically assigned to one of the 72 regions. Accumulators sum pixel values while counters track pixel counts. After processing the full frame, division of accumulated sums by their counts implements a box filter, resulting in a compact (9 \times 8) representation of the original image.

> 💡 This eliminates the need for full-frame buffering and enables real-time processing within the limited BRAM of the FPGA.

---

### 2️⃣ dHash Generation (64-bit Signature)

The (9 \times 8) image is converted into a compact 64-bit hash.

#### ⚙️ Logic:

* Perform **horizontal comparisons**
* For each pair:
  if Pixel[n] > Pixel[n+1] → 1
  else → 0

#### 📊 Result:

* 64 comparisons → **64-bit hash**
* Captures **relative intensity gradients**

> ✅ Robust against uniform brightness changes

---

### 3️⃣ Hamming Distance Computation

* Two hashes are compared using:

  * **XOR operation**
  * **Population Count (PopCount)**

#### 📊 Output:

* Number of differing bits = **Hamming Distance**

---

### 4️⃣ Duplicate Detection Logic

* Threshold: **10**

#### 🚀 Decision Rule:

If Distance ≤ 10 → Duplicate Image Detected → Discard frame
Else → Unique Image → Store/Transmit

#### 🎯 Why Threshold = 10?

* Allows minor variations (sensor noise, lighting flicker)
* Prevents false duplicate rejection
* Balances sensitivity and robustness

---

## ⚠️ Operational Challenges & Limitations

* **Aggressive Downsampling**
  (640 \times 480 → 9 \times 8) may remove fine details

* **Lighting Sensitivity**
  Extreme changes (sunrise/sunset) affect gradients

* **Pose Variation**
  Object movement can flip multiple bits

* **Simulation vs Real-World Gap**
  Real sensor noise differs from simulation conditions

---

## 📂 Repository Structure

/src → Verilog source (accumulators, dHash, comparator)
/sim → Testbench & simulation outputs
/docs → Architecture diagrams, waveforms, PPT
/video → Demo & explanation
README.md

---

## 🛠️ Hardware Specifications

* **FPGA:** Digilent Basys 3 (Artix-7)
* **Input:** 8-bit grayscale pixel stream (OV7670)
* **Output:** 64-bit hash + duplicate flag
* **Clock:** 100 MHz
* **Memory Usage:** No full-frame buffer (BRAM-efficient)

---

## 🧠 Key Innovation

“The system performs real-time image duplicate detection using on-the-fly accumulation and hash-based comparison, eliminating the need for full-frame memory on FPGA.”

---

## 🔮 Future Scope

* Multi-scale hashing for improved accuracy
* Adaptive thresholding
* Edge AI integration
* IoT-based wildlife monitoring systems

---

## 📊 Deliverables

* Verilog source code
* Simulation waveforms
* Project PPT
* Demo video

---

## 👥 Team: The MOSFET Mob
[Member Names]: 
Harsh Lad
Archit Langde
Aryan Chaudhary
Hrishikesh Dhume

Developed for the **UNPLUGGED Hardware Hackathon**
