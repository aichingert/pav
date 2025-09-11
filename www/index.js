var importObject = {
    env: {
        console_log: (arg) => console.log(arg),
    },
};

WebAssembly.instantiateStreaming(fetch("zig-out/bin/pav.wasm"), importObject).then((result) => {
    console.log(result.instance.exports);
    console.log(result.instance.exports.add(1, 2));
    //result.instance.exports..extract_pixels_from_png("hello.png");
});
