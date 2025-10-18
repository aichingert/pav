window.onload = async () => {
    let width;
    let height;
    let pixels;

    const drop_area = document.getElementById("drop-area");
    const upload_picture = document.getElementById("picture");

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

    function init_app() {
        drop_area.remove();
        upload_picture.remove();

        const canvas = document.createElement("canvas");
        canvas.id = "image-showcase";
        canvas.width = width;
        canvas.height = height;

        document.body.appendChild(canvas);

        let ctx = canvas.getContext("2d");
        let img = ctx.getImageData(0, 0, width, height);

        for (let i = 0; i < height; i++) {
            for (let j = 0; j < width; j++) {
                let pos = i * width + j;
                let off = pos * 4;

                img.data[off + 2] = (pixels[pos] >> 0)  & 0xFF;
                img.data[off + 1] = (pixels[pos] >> 8)  & 0xFF;
                img.data[off + 0] = (pixels[pos] >> 16) & 0xFF;
                img.data[off + 3] = 0xFF;
            }
        }

        ctx.putImageData(img, 0, 0);
        console.log(img);

    }

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
            width = image_get_width(img_ptr);
            height = image_get_height(img_ptr);
            pixels = new Uint32Array(memory.buffer, image_get_pixels(img_ptr), width * height);
            init_app();
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

