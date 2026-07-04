use std::path::Path;
use std::process::exit;

fn print_usage() {
    eprintln!("usage: logo-bg-remover-cli --input <path.png|jpg> --output <path.png>");
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut input: Option<String> = None;
    let mut output: Option<String> = None;

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

    println!("Checking for local model (downloads ~176MB on first run)...");
    let model_path = match logo_bg_remover::ensure_model_downloaded() {
        Ok(p) => p,
        Err(e) => {
            eprintln!("ERROR: {e}");
            exit(1);
        }
    };

    println!("Removing background...");
    match logo_bg_remover::remove_background(&model_path, Path::new(&input), Path::new(&output)) {
        Ok(()) => println!("OK: wrote {output}"),
        Err(e) => {
            eprintln!("ERROR: {e}");
            exit(1);
        }
    }
}
