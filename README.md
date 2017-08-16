# Eggshell

Eggshell is a highly flexible and powerful plaintext to HTML processor. Out of the box, it can:

1. Nest inline formatting while also passing in arbitrary attributes
2. Include external files for processing
3. Support if/else constructs and loops
4. Dynamically create and retrieve variables (including maps and hashes), perform logical operations, and call functions

The interface allows for easily overriding and extending functionality (including new inline markup syntax). See `sample.eggshell` for a crash course.

## Installation

`gem install eggshell`

## Usage

From the command line:

`eggshell $file.eggshell > $output.html`

From code:

`require 'eggshell'
eggshell = Eggshell::Processor.new
Eggshell::Bundles::Registry.attach_bundle('basics', eggshell)

html = eggshell.process(IO.readlines('path/to/file'))
`