use winit::{
    event::{Event, WindowEvent},
    event_loop::EventLoop,
    window::{Window, WindowAttributes},
};

mod ttf;
mod state;

mod app;
use app::App;

fn main() {
    let ev_loop = EventLoop::new().unwrap();
    let window = ev_loop.create_window(WindowAttributes::default()).unwrap();

    ttf::Parser::new("PxPlus_ToshibaTxL1_8x16.ttf");

    pollster::block_on(App::run(ev_loop, &window));
}
