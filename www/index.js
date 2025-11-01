window.onload = async () => {
    let image;
    let width;
    let height;
    let pixels;

    let edit_selected = false;
    let thickness_selected = false;

    home.style.display = "";
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

    // setup events
    shuffle_btn.onclick = () => set_voronoied_image(raw_pixels, pixel_slider.value, !edit_selected);
    edit_btn.onclick = () => {
        edit_selected = !edit_selected;
        if (edit_selected) {
            raw_pixels.classList.add("circle-cursor");
            //set_image(raw_pixels, pixels, false);

            edit_btn.style.background = "var(--main-gren)";
            edit_bar.style.display = ""; 
            bottom_row.style.gridTemplateColumns = "15% auto";
        } else {
            // TODO: add multiple sizes and change depending on thickness
            raw_pixels.classList.remove("circle-cursor");
            //set_image(raw_pixels, pixels, true);

            edit_btn.style.background = "var(--main-light-light-gray)";
            edit_bar.style.display = "none"; 
            bottom_row.style.gridTemplateColumns = "100%";
        }
    }
    thickness_btn.onclick = () => {
        thickness_selected = !thickness_selected;
        if (thickness_selected) {
            thickness_btn.style.background = "var(--main-blue)";
            thickness_sld.style.display = "";
        } else {
            thickness_btn.style.background = "var(--main-lightl-light-gray)";
            thickness_sld.style.display = "none";
        }
    };

    raw_pixels.onmousedown = (event) => {
        if (!edit_selected) return;

        const rect = raw_pixels.getBoundingClientRect();
        const x = event.clientX - rect.left;
        const y = event.clientY - rect.top;
        console.log(x);
        console.log(y);
    }

    function set_image(canvas, pxls, should_scale) {
        // TODO: remove this
        should_scale = true;
        if (!should_scale) {
            console.log(width, height);
            canvas.width = width;
            canvas.height = height;

            let ctx = canvas.getContext("2d");
            let img = ctx.getImageData(0, 0, width, height);

            for (let i = 0; i < height; i++) {
                for (let j = 0; j < width; j++) {
                    let pos = i * width + j;
                    let off = pos * 4;

                    img.data[off + 2] = (pxls[pos] >> 0)  & 0xFF;
                    img.data[off + 1] = (pxls[pos] >> 8)  & 0xFF;
                    img.data[off + 0] = (pxls[pos] >> 16) & 0xFF;
                    img.data[off + 3] = 0xFF;
                }
            }

            ctx.putImageData(img, 0, 0);
            return;
        }

        const w_width = window.innerWidth - 50;
        const w_height = window.innerHeight - (window.innerHeight / 3);
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

    function set_voronoied_image(canvas, pxls, should_scale) {
        let cpy = image_copy(image);
        let val = Math.floor(pxls);

        apply_voronoi(cpy, 0, val);
        let cpx = new Uint32Array(memory.buffer, image_get_pixels(cpy), width * height);
        set_image(canvas, cpx, should_scale);

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

        const size   = Math.min(50_000, width * height) + 1;
        const init   = Math.floor(size / 2);
        let value = init;
        pixel_slider.max = size.toString();
        pixel_slider.value = value;
        pixel_slider.step = Math.floor((size / 5_000)).toString();
        pixel_slider.oninput = (event) => {
            let current = Math.max(1, event.target.valueAsNumber - 1);
            if (value == current) {
                return;
            }
            if (value == 1) {
                current -= 1;
            }

            value = current;
            pixel_slider.value = value;
            number_input.value = value;
            set_voronoied_image(raw_pixels, pixel_slider.value, !edit_selected);
        }

        number_input.max = size.toString();
        number_input.value = init;
        number_input.oninput = (event) => {
            if(isNaN(event.target.valueAsNumber) || !/^([0-9]*)$/.test(event.target.value) || event.target.valueAsNumber > size * 10) {
                number_input.value = value;
                return;
            }

            value = event.target.valueAsNumber;
            pixel_slider.value = value;
            set_voronoied_image(raw_pixels, value, !edit_selected);
        };

        set_image(raw_pixels, pixels, true);
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

