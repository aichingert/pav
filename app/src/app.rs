use winit::{
    event::WindowEvent,
    event_loop::{ActiveEventLoop, EventLoop},
    window::{Window, WindowId},
    application::ApplicationHandler, 
};

use crate::state::State;

pub struct App<'a> {
    state: State<'a>,
}

impl<'a> App<'a> {
    pub async fn new(window: &'a Window) -> Self {
        Self {
            state: State::new(window).await,
        }
    }

    pub async fn run(ev: EventLoop<()>, window: &'a Window) {
        ev.run_app(&mut Self::new(&window).await).unwrap();
    }
}

impl<'a> ApplicationHandler for App<'a> {
    fn resumed(&mut self, ev: &ActiveEventLoop) {}

    fn window_event(&mut self, ev: &ActiveEventLoop, window_id: WindowId, event: WindowEvent) {
        match event {
            WindowEvent::CloseRequested => {
                ev.exit();
            },
            WindowEvent::RedrawRequested => {
                match self.state.render() {
                    Ok(_) => (),
                    Err(wgpu::SurfaceError::Lost) => self.state.resize(self.state.size),
                    Err(wgpu::SurfaceError::OutOfMemory) => ev.exit(),
                    Err(e) => eprintln!("{:?}", e),
                }

            },
            WindowEvent::Resized(physical_size) => {
                self.state.resize(physical_size);
            },
            _ => (),
        }
    }
}
