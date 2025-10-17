window.onload = async () => {
    const wasm = await WebAssembly.instantiateStreaming(
        fetch("pav.wasm"), 
        {
            env: {
                debug_log: (ptr, len) => {
                    const bytes = new Uint8Array(wasm.instance.exports.memory.buffer, ptr, len);
                    const strvl = new TextDecoder().decode(bytes);
                    console.log(strvl);
                },
            },
        },
    );

    //let name = "hello.png";
    //let encoder = new TextEncoder();
    //let bytes = encoder.encode(name);
    //let addr  = wasm.instance.exports.alloc(bytes.byteLength);
    //let dest  = new Uint8Array(wasm.instance.exports.memory.buffer, addr, bytes.byteLength);
    //encoder.encodeInto(name, dest);

    //let result = wasm.instance.exports.parse_image(addr, bytes.byteLength, addr);
    //console.log(wasm.instance.exports, result);
    //wasm.instance.exports.free(addr, bytes.byteLength);

    const upload_picture = document.getElementById("picture");

    upload_picture.addEventListener("change", (event) => {
        if (event.target.files.length <= 0) {
            return;
        }

        const reader = new FileReader();
        reader.onload = () => {
            console.log(reader.result);
            const tenc = new TextEncoder();
            const tdec = new TextDecoder();

            const image_path = tenc.encode(event.target.files[0].name);
            const image_data = tenc.encode(reader.result);

            const path_addr = wasm.instance.exports.alloc(image_path.byteLength);
            const data_addr = wasm.instance.exports.alloc(image_data.byteLength);

            const path_dest = new Uint8Array(wasm.instance.exports.memory.buffer, path_addr, image_path.byteLength);
            const data_dest = new Uint8Array(wasm.instance.exports.memory.buffer, data_addr, image_data.byteLength);

            tenc.encodeInto(event.target.files[0].name, path_dest);
            tenc.encodeInto(reader.result, data_dest);

            let result = wasm.instance.exports.parse_image(
                path_addr, 
                image_path.byteLength, 
                data_addr, 
                image_data.byteLength);
            console.log(result);
        };
        reader.readAsText(event.target.files[0]);
    });

    const drop_area = document.getElementById("drop-area");
    drop_area.addEventListener("dragover", (event) => {
        event.stopPropagation();
        event.preventDefault();
        event.dataTransfer.dropEffect = "copy";
    });

    drop_area.addEventListener("drop", (event) => {
        event.stopPropagation();
        event.preventDefault();
        const fileList = event.dataTransfer.files;
    });

    drop_area.addEventListener("click", (event) => {
        upload_picture.click();
    });
}

