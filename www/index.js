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

    function init_app() {
        drop_area.style.display = "none";
        upload_picture.style.display = "none";

        const container = document.createElement("div");
        container.style = "display: flex; flex-direction: column; justify-content: center; align-items: center";

        const tool_bar  = document.createElement("div");
        tool_bar.style.gap = "20px";
        tool_bar.style.display = "flex";
        tool_bar.style.padding = "15px 50px 15px 50px";
        tool_bar.style.marginBottom = "20px";
        tool_bar.style.borderRadius = "25px";
        tool_bar.style.backgroundColor = "var(--main-light-gray)";
 
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
            set_voronoied_image(canvas, value);
        };

        const button = document.createElement("button");
        button.innerHTML = "randomize";
        button.style.padding = "1rem";
        button.style.color = "hsl(0, 0%, 95%)";
        button.style.fontSize = "15px";
        button.style.fontWeight = "bolder";
        button.style.background = "var(--main-light-light-gray)";
        button.style.boxShadow = "inset 0 1px 2px #ffffff70, 0 1px 2px #00000030, 0 2px 4px #00000015"
        button.onmouseover = () => button.style.background = "var(--main-gren)";
        button.onmouseout = () => button.style.background = "var(--main-light-light-gray)";

        button.onclick = () => set_voronoied_image(canvas, slider.value);

        tool_bar.appendChild(slider);
        tool_bar.appendChild(num_inp);
        tool_bar.appendChild(button);
        container.appendChild(tool_bar);

        const canvas = document.createElement("canvas");
        canvas.id = "image-showcase";
        set_image_scaled(canvas, pixels);

        container.appendChild(canvas);
        document.body.appendChild(container);
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

