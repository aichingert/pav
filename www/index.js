window.onload = async () => {
    let image;
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
                rand: () => {
                    const upper_bound = 2 << 16;
                    return Math.floor(Math.random() * upper_bound);
                }
            },
        },
    );
    const { 
        alloc, 
        free, 
        wasm_array_init, 
        image_get_width,
        image_get_height,
        image_get_pixels,
        image_copy,
        image_free,
        parse_image, 
        apply_voronoi,
        memory,
    } = wasm.instance.exports;

    function init_app() {
        drop_area.remove();
        upload_picture.remove();

        const canvas = document.createElement("canvas");
        canvas.id = "image-showcase";
        canvas.width = width;
        canvas.height = height;

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

        const button = document.createElement("button");
        button.innerHTML = "randomize";
        button.onclick = () => {
            let cpy = image_copy(image);

            apply_voronoi(cpy);
            let cpx = new Uint32Array(memory.buffer, image_get_pixels(cpy), width * height);

            for (let i = 0; i < height; i++) {
                for (let j = 0; j < width; j++) {
                    let pos = i * width + j;
                    let off = pos * 4;

                    img.data[off + 2] = (cpx[pos] >> 0)  & 0xFF;
                    img.data[off + 1] = (cpx[pos] >> 8)  & 0xFF;
                    img.data[off + 0] = (cpx[pos] >> 16) & 0xFF;
                    img.data[off + 3] = 0xFF;
                }
            }

            ctx.putImageData(img, 0, 0);
            image_free(cpy);
        };

        document.body.appendChild(canvas);
        document.body.appendChild(button);

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

            const file = wasm_array_init(path_ptr, image_path.byteLength);
            const data = wasm_array_init(data_ptr, image_data.byteLength);

            image = parse_image(file, data);
            width = image_get_width(image);
            height = image_get_height(image);
            pixels = new Uint32Array(memory.buffer, image_get_pixels(image), width * height);
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

