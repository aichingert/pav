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
        const w_width = window.innerWidth - 50;
        const w_height = 3 * window.innerHeight / 4;
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
        drop_area.style.display = "none";
        upload_picture.style.display = "none";

        const container = document.createElement("div");
        container.style.display = "grid";
        container.style.gap = "15px";
        container.style.justifyContent = "center";
        container.style.alignItems = "center";
        container.style.gridTemplateAreas = `"tool-bar tool-bar" "edit-bar image-showcase"`;
        //container.style = "display: flex; flex-direction: column; justify-content: center; align-items: center";

        const tool_bar  = document.createElement("div");
        //tool_bar.style.gap = "20px";
        tool_bar.style.display = "flex";
        tool_bar.style.padding = "15px 50px 15px 50px";
        tool_bar.style.borderRadius = "25px";
        tool_bar.style.backgroundColor = "var(--main-light-gray)";
        tool_bar.style.gridArea = "tool-bar";

        const edit_bar = document.createElement("div");
        edit_bar.style.gridArea = "edit-bar";
        edit_bar.style.display = "flex";
        edit_bar.style.padding = "50px 15px 50px 15px";
        edit_bar.style.borderRadius = "25px";
        edit_bar.style.backgroundColor = "var(--main-light-gray)";

        const eraser_btn = document.createElement("button");

        const eraser_icon = eraserIcon.content.cloneNode(true).children[0];
        eraser_icon.style   = "width: 40px; height: 40px";

        eraser_btn.style.padding = "1rem";
        eraser_btn.style.background = "var(--main-light-light-gray)";
        eraser_btn.style.boxShadow = "inset 0 1px 2px #ffffff30, 0 1px 2px #00000030, 0 2px 4px #00000015"
        eraser_btn.appendChild(eraser_icon);
        edit_bar.appendChild(eraser_btn);
        
        //edit_bar.style.display = "none";

        const slider = document.createElement("input");
        const size   = Math.min(100_000, Math.floor((width * height) / 8));
        const init   = Math.floor(size / 2);
        slider.type = "range";
        slider.min = "1";
        slider.max = size.toString();
        slider.value = init;
        slider.step = (size / 10_000).toString();
        slider.oninput = (event) => {
            num_inp.value = Math.floor(event.target.valueAsNumber);
            set_voronoied_image(canvas, slider.value);
        }

        const num_inp = document.createElement("input");
        num_inp.type = "number";
        num_inp.style = `
            padding: 1rem;
            color: var(--main-blue); 
            background: var(--main-light-light-gray); 
            border-style: none; 
            align-items: center;
            font-size: 15px;
            font-weight: bolder;
        `;
        num_inp.style.boxShadow = "inset 0 1px 2px #ffffff30, 0 1px 2px #00000030, 0 2px 4px #00000015"
        num_inp.min = "1";
        num_inp.max = size.toString();
        num_inp.value = init;
        num_inp.onbeforeinput = (event) => {
            if(!/^([0-9]*)$/.test(event.data ?? "")) {
                event.preventDefault();
            }
            return;
        };
        num_inp.oninput = (event) => {
            const value = event.target.valueAsNumber;
            slider.value = value;
            set_voronoied_image(canvas, value);
        };
        num_inp.onmouseover = () => num_inp.style.background = "var(--main-gren)";
        num_inp.onmouseout = () => num_inp.style.background = "var(--main-light-light-gray)";

        const shuffle_btn = document.createElement("button");
        const edit_btn    = document.createElement("button");
        const export_btn  = document.createElement("button");

        const dice_icon   = diceIcon.content.cloneNode(true).children[0];
        dice_icon.style   = "width: 40px; height: 40px";
        const pencil_icon = pencilIcon.content.cloneNode(true).children[0];
        pencil_icon.style = "width: 40px; height: 40px";
        // TODO: tweak colors a bit better to not make it look so weird
        const export_icon = exportIcon.content.cloneNode(true).children[0];
        export_icon.style = "width: 40px; height: 40px";

        shuffle_btn.style.padding = "1rem";
        shuffle_btn.style.background = "var(--main-light-light-gray)";
        shuffle_btn.style.boxShadow = "inset 0 1px 2px #ffffff30, 0 1px 2px #00000030, 0 2px 4px #00000015"
        shuffle_btn.appendChild(dice_icon);

        shuffle_btn.onclick = () => set_voronoied_image(canvas, slider.value);
        shuffle_btn.onmouseover = () => shuffle_btn.style.background = "var(--main-blue)";
        shuffle_btn.onmouseout = () => shuffle_btn.style.background = "var(--main-light-light-gray)";

        edit_btn.appendChild(pencil_icon);
        edit_btn.style.padding = "1rem";
        edit_btn.style.background = "var(--main-light-light-gray)";
        edit_btn.style.boxShadow = "inset 0 1px 2px #ffffff30, 0 1px 2px #00000030, 0 2px 4px #00000015"
        edit_btn.onmouseover = () => edit_btn.style.background = "var(--main-gren)";
        edit_btn.onmouseout = () => edit_btn.style.background = "var(--main-light-light-gray)";

        export_btn.appendChild(export_icon);
        export_btn.style.padding = "1rem";
        export_btn.style.background = "var(--main-light-light-gray)";
        export_btn.style.boxShadow = "inset 0 1px 2px #ffffff30, 0 1px 2px #00000030, 0 2px 4px #00000015"
        export_btn.onmouseover = () => export_btn.style.background = "var(--main-blue)";
        export_btn.onmouseout = () => export_btn.style.background = "var(--main-light-light-gray)";

        tool_bar.appendChild(slider);
        tool_bar.appendChild(num_inp);
        tool_bar.appendChild(shuffle_btn);
        tool_bar.appendChild(edit_btn);
        tool_bar.appendChild(export_btn);
        container.appendChild(tool_bar);
        container.appendChild(edit_bar);

        const canvas = document.createElement("canvas");
        canvas.id = "image-showcase";
        canvas.style.gridArea = "image-showcase";
        canvas.style.border = "1px solid var(--main-light-light-gray)";
        canvas.style.borderRadius = "25px";
        canvas.style.padding = "1rem";
        canvas.style.boxShadow = "inset 0 1px 2px #ffffff30, 0 1px 2px #00000030, 0 2px 4px #00000015"
        set_image_scaled(canvas, pixels);

        container.appendChild(canvas);
        document.body.appendChild(container);
    }

    upload_picture.addEventListener("change", (event) => {
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
        upload_picture.click();
    });
}

