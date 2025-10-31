window.onload = async () => {
    let image;
    let width;
    let height;
    let pixels;
    app.style.display = "none";

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
        const w_width = window.innerWidth - 50;
        const w_height = window.innerHeight - (window.innerHeight / 3);
        console.log(w_width, w_height);
        const is_up = width < w_width && height < w_height;

        const scale = Math.ceil(is_up
            ? Math.min(w_width / width, w_height / height)
            : Math.max(width / w_width, height / w_height)
        );
        canvas.width = is_up ? width * scale  : Math.floor(width / scale);
        canvas.height = is_up ? height * scale : Math.floor(height / scale);

        let ctx = canvas.getContext("2d");
        let img = ctx.getImageData(0, 0, canvas.width, canvas.height);

        if (is_up) {
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
        } else {
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
        } 

        ctx.putImageData(img, 0, 0);
    }

    function set_voronoied_image(canvas, pixels) {
        let cpy = image_copy(image);
        let val = Math.floor(pixels);

        apply_voronoi(cpy, 0, val);
        let cpx = new Uint32Array(memory.buffer, image_get_pixels(cpy), width * height);
        set_image_scaled(canvas, cpx);

        image_free(cpy);
    }

    function process_file_in_wasm(f) {
        const reader = new FileReader();
        reader.onload = () => {
            const tenc = new TextEncoder();
            const tdec = new TextDecoder();

            const image_path = tenc.encode(f.name);
            const image_data = new Uint8Array(reader.result);

            const path_ptr = alloc(image_path.byteLength);
            const data_ptr = alloc(image_data.byteLength);

            const path_dest = new Uint8Array(memory.buffer, path_ptr, image_path.byteLength);
            tenc.encodeInto(f.name, path_dest);

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

        reader.readAsArrayBuffer(f);
    }

    function init_app() {
        home.style.display = "none";
        app.style.display = "grid";

        const size   = Math.min(50_000, Math.floor((width * height) / 8));
        const init   = Math.floor(size / 2);
        pixel_slider.max = size.toString();
        pixel_slider.value = init;
        pixel_slider.step = (size / 5_000).toString();
        pixel_slider.oninput = (event) => {
            number_input.value = Math.floor(event.target.valueAsNumber);
            set_voronoied_image(raw_pixels, pixel_slider.value);
        }

        number_input.max = size.toString();
        number_input.value = init;
        number_input.onbeforeinput = (event) => {
            if(!/^([0-9]*)$/.test(event.data ?? "") || (event.data ?? 0) > size) {
                event.preventDefault();
            }
            return;
        };
        number_input.oninput = (event) => {
            const value = event.target.valueAsNumber;
            pixel_slider.value = value;
            set_voronoied_image(raw_pixels, value);
        };
        shuffle_btn.onclick = () => set_voronoied_image(raw_pixels, pixel_slider.value);

        set_image_scaled(raw_pixels, pixels);
    }

    picture_upload.addEventListener("change", (event) => {
        if (event.target.files.length <= 0) {
            return;
        }

        process_file_in_wasm(event.target.files[0]);
    });

    drop_area.addEventListener("dragover", (event) => {
        event.stopPropagation();
        event.preventDefault();
        event.dataTransfer.dropEffect = "copy";
    });

    drop_area.addEventListener("drop", (event) => {
        event.stopPropagation();
        event.preventDefault();
        const file_list = event.dataTransfer.files;

        if (file_list.length <= 0) {
            return;
        }

        process_file_in_wasm(file_list[0]);
    });

    drop_area.addEventListener("click", (event) => {
        picture_upload.click();
    });
}

