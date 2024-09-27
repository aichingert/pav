use winit::{
    event::{Event, WindowEvent},
    event_loop::EventLoop,
    window::{Window, WindowAttributes},
};

mod ttf;
use ttf::parser::FontDirectory;
mod state;

mod app;
use app::App;

fn main() {

    let file: Vec<u8> = std::fs::read("../tmp/envy/envy_code.ttf").unwrap();

    let f = FontDirectory::read_section(&file);
    println!("{f:?}");

    let ev_loop = EventLoop::new().unwrap();
    let window = ev_loop.create_window(WindowAttributes::default()).unwrap();

    pollster::block_on(App::run(ev_loop, &window));
}
