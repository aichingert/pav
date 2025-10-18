window.onload = async () => {
    let pixels;

    const drop_area = document.getElementById("drop-area");
    const upload_picture = document.getElementById("picture");

    function setup_app() {
        drop_area.remove();
        upload_picture.remove();
    }

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
    const { 
        alloc, 
        free, 
        init, 
        image_get_width,
        image_get_height,
        image_get_pixels,
        parse_image, 
        memory,
    } = wasm.instance.exports;

    upload_picture.addEventListener("change", (event) => {
        if (event.target.files.length <= 0) {
            return;
        }

        const reader = new FileReader();
        reader.onload = () => {
            const tenc = new TextEncoder();
            const tdec = new TextDecoder();

            const image_path = tenc.encode(event.target.files[0].name);
            const image_data = new Uint8Array(reader.result);

            const path_ptr = alloc(image_path.byteLength);
            const data_ptr = alloc(image_data.byteLength);

            const path_dest = new Uint8Array(memory.buffer, path_ptr, image_path.byteLength);
            tenc.encodeInto(event.target.files[0].name, path_dest);

            const data_dest = new Uint8Array(memory.buffer, data_ptr, image_data.byteLength);
            data_dest.set(image_data);

            const file = init(path_ptr, image_path.byteLength);
            const data = init(data_ptr, image_data.byteLength);

            const img_ptr = parse_image(file, data);
            const img_len = image_get_width(img_ptr) * image_get_height(img_ptr);
            pixels = new Uint32Array(memory.buffer, image_get_pixels(img_ptr), img_len);
            setup_app();
        };
        reader.readAsArrayBuffer(event.target.files[0]);
    });

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

