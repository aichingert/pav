var importObject = {
    env: {
        console_log: (arg) => console.log(arg),
    },
};

WebAssembly.instantiateStreaming(fetch("zig-out/bin/pav.wasm"), importObject).then((result) => {
    console.log(result.instance.exports);
    result.instance.exports.Png.extract_pixels_from_png("hello.png");
});
