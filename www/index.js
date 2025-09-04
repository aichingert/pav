var importObject = {
    env: {
        console_log: (arg) => console.log(arg),
    },
};

WebAssembly.instantiateStreaming(fetch("zig-out/bin/pav.wasm"), importObject).then((result) => {
    result.instance.exports.extract_pixels_from_png("hello.png");
});
