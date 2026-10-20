# Protocol research references

Original Swift implementation, no vendored packages or vendor code.
No user configuration database or source-derived reference is bundled.

- MXControl by wiscaksono, MIT, commit `915068092790891a3c8532a7b9deabf6ec1ecde1`: https://github.com/wiscaksono/MXControl/tree/915068092790891a3c8532a7b9deabf6ec1ecde1
- OpenLogi by AprilNEA and contributors, project MIT/Apache-2.0, commit `abc815acf9ebb4df06ccc574016bad2c9b4152ee`: https://github.com/AprilNEA/OpenLogi/tree/abc815acf9ebb4df06ccc574016bad2c9b4152ee

Read for protocol interoperability: BLE vendor usage FF43:0202, routing index 1,
20-byte report 0x11; root and feature table; 0x2201 sensor-index echo and E000 range
markers; 0x1B04 temporary diversion flags; 0x2110/2111 wheel mode; 0x40A0/40A2/40A3
Fn inversion; 0x1982 v3 backlight field preservation and readback. Not all reference
implementations agree on every detail. Unknown protocol versions are not evidence
of supported behavior. No GPL-derived implementation is included.

Apple SDK frameworks are linked under the applicable Apple SDK terms. Product names
identify compatible hardware and do not imply Logitech endorsement.

## Device renders

The `lite-mouse.png`, `lite-mouse-rear.png`, and `lite-keyboard.png` device
renders are derived from owner-supplied Options+ screenshots. They depict
third-party products and are for personal local use. Replace or remove them
before public distribution unless appropriate rights are confirmed. The app
falls back to vector drawings if an image is missing.
