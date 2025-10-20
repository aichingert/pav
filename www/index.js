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

    function set_image_scaled(canvas, pxls) {
        let ctx = canvas.getContext("2d");
        let scale = 1;

        if (width < canvas.width && height < canvas.height) {
            while ((scale + 1) * width < canvas.width && (scale + 1) * height < canvas.height) {
                scale += 1;
            }

            let img = ctx.getImageData(0, 0, width * scale, height * scale);

            for (let y = 0; y < height; y++) {
                for (let ys = 0; ys < scale; ys++) {
                    for (let x = 0; x < width; x++) {
                        for (let xs = 0; xs < scale; xs++) {
                            const pos = y * width + x;
                            const yp = y * width * scale * scale + ys * width * scale;
                            const xp = x * scale + xs;
                            const off = (yp + xp) * 4;

                            img.data[off + 2] = (pxls[pos] >> 0)  & 0xFF;
                            img.data[off + 1] = (pxls[pos] >> 8)  & 0xFF;
                            img.data[off + 0] = (pxls[pos] >> 16) & 0xFF;
                            img.data[off + 3] = 0xFF;
                        }
                    }
                }
            }

            ctx.putImageData(img, 0, 0);
        } else {
            while ((1 / scale) * width > canvas.width || (1 / scale) * height > canvas.height) {
                scale += 1;
            }

            let img = ctx.getImageData(0, 0, Math.floor(width / scale), Math.floor(height / scale));

            for (let y = 0; y < height; y += scale) {
                for (let x = 0; x < width; x += scale) {
                    let avg_r = 0;
                    let avg_g = 0;
                    let avg_b = 0;
                    let cnt = 0;

                    for (let ys = 0; ys < scale; ys++) {
                        for (let xs = 0; xs < scale; xs++) {
                            if (y + ys >= height || x + xs >= width) {
                                continue;
                            }

                            const pos = (y + ys) * width + x + xs;
                            avg_r += (pxls[pos] >> 16) & 0xFF;
                            avg_g += (pxls[pos] >> 8) & 0xFF;
                            avg_b += (pxls[pos] >> 0) & 0xFF;
                            cnt += 1;
                        }
                    }

                    const pos = y * width + x;
                    const off = ((y / scale) * Math.floor((width / scale)) + (x / scale)) * 4;

                    img.data[off + 0] = avg_r / cnt;
                    img.data[off + 1] = avg_g / cnt;
                    img.data[off + 2] = avg_b / cnt;
                    img.data[off + 3] = 0xFF;
                }
            } 

            ctx.putImageData(img, 0, 0);
        } 
    }

    function init_app() {
        drop_area.remove();
        upload_picture.remove();

        console.log(window.innerWidth);
        console.log(window.innerHeight);

        const canvas = document.createElement("canvas");
        canvas.id = "image-showcase";
        canvas.style = "display: block;";
        canvas.width = 3 * window.innerWidth / 4;
        canvas.height = 3 * window.innerHeight / 4;

        set_image_scaled(canvas, pixels);
 
        const slider = document.createElement("input");
        const size   = Math.min(100_000, Math.floor((width * height) / 8));
        const init   = Math.floor(size / 2);
        slider.type = "range";
        slider.min = "1";
        slider.max = size.toString();
        slider.value = init;
        slider.step = (size / 10000).toString();
        slider.oninput = (event) => num_inp.value = Math.floor(event.target.valueAsNumber);

        const num_inp = document.createElement("input");
        num_inp.type = "number";
        num_inp.min = "1";
        num_inp.max = size.toString();
        num_inp.value = init;
        num_inp.oninput = (event) => {
            const value = event.target.valueAsNumber;

            if (isNaN(value)) {
                // TODO: error message
                return;
            }

            slider.value = value;
        };

        const button = document.createElement("button");
        button.innerHTML = "randomize";
        button.onclick = () => {
            let cpy = image_copy(image);
            let val = Math.floor(slider.value);

            apply_voronoi(cpy, 0, val);
            let cpx = new Uint32Array(memory.buffer, image_get_pixels(cpy), width * height);
            set_image_scaled(canvas, cpx);

            image_free(cpy);
        };
 
        document.body.appendChild(canvas);
        document.body.appendChild(slider);
        document.body.appendChild(num_inp);
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

