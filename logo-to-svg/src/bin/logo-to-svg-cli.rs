use std::path::Path;
use std::process::exit;

fn print_usage() {
    eprintln!(
        "usage: logo-to-svg-cli --input <path.png> --output <path.svg> \
         [--color-precision N] [--filter-speckle N] [--corner-threshold N]"
    );
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut input: Option<String> = None;
    let mut output: Option<String> = None;
    let mut opts = logo_to_svg::SvgOptions::default();

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--input" => {
                input = args.get(i + 1).cloned();
                i += 2;
            }
            "--output" => {
                output = args.get(i + 1).cloned();
                i += 2;
            }
            "--color-precision" => {
                if let Some(v) = args.get(i + 1).and_then(|s| s.parse().ok()) {
                    opts.color_precision = v;
                }
                i += 2;
            }
            "--filter-speckle" => {
                if let Some(v) = args.get(i + 1).and_then(|s| s.parse().ok()) {
                    opts.filter_speckle = v;
                }
                i += 2;
            }
            "--corner-threshold" => {
                if let Some(v) = args.get(i + 1).and_then(|s| s.parse().ok()) {
                    opts.corner_threshold = v;
                }
                i += 2;
            }
            _ => {
                i += 1;
            }
        }
    }

    let (input, output) = match (input, output) {
        (Some(i), Some(o)) => (i, o),
        _ => {
            print_usage();
            exit(2);
        }
    };

    match logo_to_svg::convert_to_svg(Path::new(&input), Path::new(&output), &opts) {
        Ok(()) => println!("OK: wrote {output}"),
        Err(e) => {
            eprintln!("ERROR: {e}");
            exit(1);
        }
    }
}
