"""Rules and helper functions for extracting data from json files"""

def json_extractor(ctx, input_file, output_file, template):
    """Extract data into output_file from input_file using the provided Go template

    Args:
        ctx: The context of the rule.
        input_file: Input json file.
        output_file: Output text file.
        template: Go template to render.
    """

    args = ctx.actions.args()
    args.add("-input", input_file)
    args.add("-output", output_file)
    args.add("-template", template)

    ctx.actions.run(
        executable = ctx.executable._json_extractor,
        mnemonic = "JsonTemplateExtractor",
        arguments = [args],
        inputs = [input_file],
        outputs = [output_file],
    )
