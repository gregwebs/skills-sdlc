# Rust

## Error handling

Panics should be avoided if possible in favor of returning an error.

Most functions should return an error instead of `None`.
The error is descriptive but `None` is opaque.

Always handle errors. Logging errors is not handling them.

## Newtype pattern

Parse, don't validate, and help ensure that with a simple new type.

Also consider creating a new type to encapsulate trait behavior.

## Linting

Use clippy for linting.

## Modules

Don't pile on new concepts to existing modules.
Keep an eye out for concepts that can go in their own module.
