# DemucsExample

1. Run `make ios` from the repository root.
2. Install XcodeGen if needed (`brew install xcodegen`).
3. Run `xcodegen generate` in this directory.
4. Open `DemucsExample.xcodeproj` and run on a device or an arm64 simulator.

Pick a model and an audio file. The app downloads the weights on first use
(84–333 MB), separates the file on the GPU, and writes each stem as a WAV you
can share. Separation is much faster on a device than in the simulator.
