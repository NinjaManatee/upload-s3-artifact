# upload-s3-artifact

Upload Actions Artifacts from your Workflow Runs to AWS S3.

See also [download-s3-artifact](https://github.com/NinjaManatee/download-s3-artifact).

- [`upload-s3-artifact`](#upload-s3-artifact)
  - [Usage](#usage)
    - [Inputs](#inputs)
    - [Outputs](#outputs)
  - [Examples](#examples)
    - [Upload an Individual File](#upload-an-individual-file)
    - [Upload an Entire Directory](#upload-an-entire-directory)
    - [Upload using a Wildcard Pattern](#upload-using-a-wildcard-pattern)
    - [Upload using Multiple Paths and Exclusions](#upload-using-multiple-paths-and-exclusions)
    - [Altering compressions level (speed v. size)](#altering-compressions-level-speed-v-size)
    - [Customization if no files are found](#customization-if-no-files-are-found)
    - [(Not) Uploading to the same artifact](#not-uploading-to-the-same-artifact)
    - [Environment Variables and Tilde Expansion](#environment-variables-and-tilde-expansion)
    - [Retention Period](#retention-period)
    - [Using Outputs](#using-outputs)
      - [Example output between steps](#example-output-between-steps)
      - [Example output between jobs](#example-output-between-jobs)
    - [Overwriting an Artifact](#overwriting-an-artifact)
  - [Limitations](#limitations)
    - [Number of Artifacts](#number-of-artifacts)
    - [Zip archives](#zip-archives)
    - [Permission Loss](#permission-loss)
  - [Where does the upload go?](#where-does-the-upload-go)
  - [The Future](#the-future)

## Usage

In general, the usage for `upload-s3-artifact` is the same as with `@NinjaManatee/upload-s3-artifact@main`, except where it isn't possible to replicate the behavior with AWS S3. For example, the `retention-days` input does not delete the object after configured number of days. It is instead the number of days the presigned URL to the object is valid. The lifecycle of objects is controlled by the S3 bucket rather than on a per item basis. We do recommend setting the S3 bucket up to delete objects that have not been access for some number of days. If `retention-days` is set to a value greater than the lifecycle of object, the URL will be invalid after the object is deleted. See [Managing the lifecycle of objects](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html) for more information.

### Inputs

This action uses the following environment variables:
    - S3_ARTIFACTS_BUCKET - the name of the AWS S3 bucket to use
    - AWS_ACCESS_KEY_ID - the AWS access key ID (optional if uploading to a public S3 bucket)
    - AWS_SECRET_ACCESS_KEY - the AWS secret access key (optional if uploading to a public S3 bucket)
    - AWS_REGION - the region of the AWS S3 bucket. Defaults to us-east-1 (optional, defaults to "us-east-1").

```yaml
- uses: NinjaManatee/upload-s3-artifact@main
  with:
    # Name of the artifact to upload.
    # Optional. Default is 'artifact'
    name:

    # A file, directory or wildcard pattern that describes what to upload
    # Required.
    path:

    # The desired behavior if no files are found using the provided path.
    # Available Options:
    #   warn: Output a warning but do not fail the action
    #   error: Fail the action with an error message
    #   ignore: Do not output any warnings or errors, the action does not fail
    # Optional. Default is 'warn'
    if-no-files-found:

    # Duration after which artifact's presigned URL will expire in days.
    # Minimum 1 day.
    # Maximum 90 days unless changed from the repository settings page.
    # Optional. Defaults 7 days.
    retention-days:

    # The level of compression for Zlib to be applied to the artifact archive.
    # The value can range from 0 to 9.
    # For large files that are not easily compressed, a value of 0 is recommended for significantly faster uploads.
    # Optional. Default is '6'
    compression-level:

    # If true, an artifact with a matching name will be deleted before a new one is uploaded.
    # If false, the action will fail if an artifact for the given name already exists.
    # Does not fail if the artifact does not exist.
    # Optional. Default is 'false'
    overwrite:

    # Whether to include hidden files in the provided path in the artifact
    # The file contents of any hidden files in the path should be validated before
    # enabled this to avoid uploading sensitive information.
    # Optional. Default is 'false'
    include-hidden-files:
```

### Outputs

| Name | Description | Example |
| - | - | - |
| `artifact-url` | Presigned URL to download an Artifact. Can be used in many scenarios such as linking to artifacts in issues or pull requests. Users must be logged-in to be able to retrieve this URL, but does not need credentials to download the object. This URL is valid as long as the artifact has not expired or the artifact, run or repository have not been deleted | `https://github.com/example-org/example-repo/actions/runs/1/artifacts/1234` |
| `artifact-digest` | SHA-256 digest of an Artifact | 0fde654d4c6e659b45783a725dc92f1bfb0baa6c2de64b34e814dc206ff4aaaf |

## Examples

### Upload an Individual File

```yaml
steps:
- run: mkdir -p path/to/artifact
- run: echo hello > path/to/artifact/world.txt
- uses: NinjaManatee/upload-s3-artifact@main
  with:
    name: my-artifact
    path: path/to/artifact/world.txt
```

### Upload an Entire Directory

```yaml
- uses: NinjaManatee/upload-s3-artifact@main
  with:
    name: my-artifact
    path: path/to/artifact/ # or path/to/artifact
```

### Upload using a Wildcard Pattern

<!-- TODO: need to verify whether this works. 
```yaml
- uses: NinjaManatee/upload-s3-artifact@main
  with:
    name: my-artifact
    path: path/**/[abc]rtifac?/*
```
-->

### Upload using Multiple Paths and Exclusions

```yaml
- uses: NinjaManatee/upload-s3-artifact@main
  with:
    name: my-artifact
    path: |
      path/output/bin/
      path/output/test-results
      !path/**/*.tmp
```
<!-- TODO: link to documentation of how the globbing works? -->

<!-- TODO: Need to verify whether this is correct
If a wildcard pattern is used, the path hierarchy will be preserved after the first wildcard pattern:

```
path/to/*/directory/foo?.txt =>
    ∟ path/to/some/directory/foo1.txt
    ∟ path/to/some/directory/foo2.txt
    ∟ path/to/other/directory/foo1.txt

would be flattened and uploaded as =>
    ∟ some/directory/foo1.txt
    ∟ some/directory/foo2.txt
    ∟ other/directory/foo1.txt
```
-->

If multiple paths are provided as input, the least common ancestor of all the search paths will be used as the root directory of the artifact. Exclude paths do not affect the directory structure.

Relative and absolute file paths are both allowed. Relative paths are rooted against the current working directory. Paths that begin with a wildcard character should be quoted to avoid being interpreted as YAML aliases. <!-- TODO: Need to take out the code that prevents copying code from outside of the project. -->

### Altering compressions level (speed v. size)

If you are uploading large or easily compressible data to your artifact, you may benefit from tweaking the compression level. By default, the compression level is `6`, the same as GNU Gzip.

The value can range from 0 to 9:
  - 0: No compression
  - 1: Best speed
  - 6: Default compression (same as GNU Gzip)
  - 9: Best compression

Higher levels will result in better compression, but will take longer to complete.
For large files that are not easily compressed, a value of `0` is recommended for significantly faster uploads.

For instance, if you are uploading random binary data, you can save a lot of time by opting out of compression completely, since it won't benefit:

```yaml
- name: Make a 1GB random binary file
  run: dd if=/dev/urandom of=my-1gb-file bs=1M count=1000
- uses: NinjaManatee/upload-s3-artifact@main
  with:
    name: my-artifact
    path: my-1gb-file
    compression-level: 0 # no compression
```

But, if you are uploading data that is easily compressed (like plaintext, code, etc) you can save space and cost by having a higher compression level. But this will be heavier on the CPU therefore slower to upload:

```yaml
- name: Make a file with a lot of repeated text
  run: |
    for i in {1..100000}; do echo -n 'foobar' >> foobar.txt; done
- uses: NinjaManatee/upload-s3-artifact@main
  with:
    name: my-artifact
    path: foobar.txt
    compression-level: 9 # maximum compression
```

### Customization if no files are found

If a path (or paths), result in no files being found for the artifact, the action will succeed but print out a warning. In certain scenarios it may be desirable to fail the action or suppress the warning. The `if-no-files-found` option allows you to customize the behavior of the action if no files are found:

```yaml
- uses: NinjaManatee/upload-s3-artifact@main
  with:
    name: my-artifact
    path: path/to/artifact/
    if-no-files-found: error # 'warn' or 'ignore' are also available, defaults to `warn`
```

<!-- TODO: Need to implement this. Currently objects are overwritten
### (Not) Uploading to the same artifact

Like `@actions/upload-artifact`, uploading to the same artifact via multiple jobs is _not_ supported.

```yaml
- run: echo hi > world.txt
- uses: NinjaManatee/upload-s3-artifact@main
  with:
    # implicitly named as 'artifact'
    path: world.txt

- run: echo howdy > extra-file.txt
- uses: NinjaManatee/upload-s3-artifact@main
  with:
    # also implicitly named as 'artifact', will fail here!
    path: extra-file.txt
```

Artifact names must be unique since each created artifact is idempotent so multiple jobs cannot modify the same artifact.

In matrix scenarios, be careful to not accidentally upload to the same artifact, or else you will encounter conflict errors. It would be best to name the artifact _with_ a prefix or suffix from the matrix:

```yaml
jobs:
  upload:
    name: Generate Build Artifacts

    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest]
        version: [a, b, c]

    runs-on: ${{ matrix.os }}

    steps:
    - name: Build
      run: ./some-script --version=${{ matrix.version }} > my-binary
    - name: Upload
      uses: NinjaManatee/upload-s3-artifact@main
      with:
        name: binary-${{ matrix.os }}-${{ matrix.version }}
        path: my-binary
```

This will result in artifacts like: `binary-ubuntu-latest-a`, `binary-windows-latest-b`, and so on.
-->

### Environment Variables and Tilde Expansion

You can use `~` in the path input as a substitute for `$HOME`. Basic tilde expansion is supported:

```yaml
  - run: |
      mkdir -p ~/new/artifact
      echo hello > ~/new/artifact/world.txt
  - uses: NinjaManatee/upload-s3-artifact@main
    with:
      name: my-artifacts
      path: ~/new/**/*
```

Environment variables along with context expressions can also be used for input. For documentation see [context and expression syntax](https://help.github.com/en/actions/reference/context-and-expression-syntax-for-github-actions):

```yaml
    env:
      name: my-artifact
    steps:
    - run: |
        mkdir -p ${{ github.workspace }}/artifact
        echo hello > ${{ github.workspace }}/artifact/world.txt
    - uses: NinjaManatee/upload-s3-artifact@main
      with:
        name: ${{ env.name }}-name
        path: ${{ github.workspace }}/artifact/**/*
```

For environment variables created in other steps, make sure to use the `env` expression syntax

```yaml
    steps:
    - run: |
        mkdir testing
        echo "This is a file to upload" > testing/file.txt
        echo "artifactPath=testing/file.txt" >> $GITHUB_ENV
    - uses: NinjaManatee/upload-s3-artifact@main
      with:
        name: artifact
        path: ${{ env.artifactPath }} # this will resolve to testing/file.txt at runtime
```

### Retention Period

The presigned URL to the artifacts are valid for 90 days by default. You can specify a shorter retention period using the `retention-days` input:

```yaml
  - name: Create a file
    run: echo "I won't live long" > my_file.txt

  - name: Upload Artifact
    uses: NinjaManatee/upload-s3-artifact@main
    with:
      name: my-artifact
      path: my_file.txt
      retention-days: 5
```

The lifecycle of objects is controlled by the S3 bucket rather than on a per item basis, and `retention-days` input is the number of days the presigned URL to the object is valid.  We do recommend setting the S3 bucket up to delete objects that have not been access for some number of days. If `retention-days` is set to a value greater than the lifecycle of object, the URL will be invalid after the object is deleted. See [Managing the lifecycle of objects](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html) for more information. 

### Overwriting an Artifact

Although it's not possible to mutate an Artifact, can completely overwrite one. But do note that this will give the Artifact a new ID, the previous one will no longer exist:

```yaml
jobs:
  upload:
    runs-on: ubuntu-latest
    steps:
      - name: Create a file
        run: echo "hello world" > my-file.txt
      - name: Upload Artifact
        uses: NinjaManatee/upload-s3-artifact@main
        with:
          name: my-artifact # NOTE: same artifact name
          path: my-file.txt
  upload-again:
    needs: upload
    runs-on: ubuntu-latest
    steps:
      - name: Create a different file
        run: echo "goodbye world" > my-file.txt
      - name: Upload Artifact
        uses: NinjaManatee/upload-s3-artifact@main
        with:
          name: my-artifact # NOTE: same artifact name
          path: my-file.txt
          overwrite: true
```

### Uploading Hidden Files

By default, hidden files are ignored by this action to avoid unintentionally uploading sensitive information.

If you need to upload hidden files, you can use the `include-hidden-files` input.
Any files that contain sensitive information that should not be in the uploaded artifact can be excluded
using the `path`:

```yaml
- uses: NinjaManatee/upload-s3-artifact@main
  with:
    name: my-artifact
    include-hidden-files: true
    path: |
      path/output/
      !path/output/.production.env
```

Hidden files are defined as any file beginning with `.` or files within folders beginning with `.`.
On Windows, files and directories with the hidden attribute are not considered hidden files unless
they have the `.` prefix.

## Limitations

### Number of Artifacts

Unlike, `@actions/upload-artifact`, you have have any number of artifacts associated within a job, but there may be implication on cost by storing large numbers of objects.
<!-- TODO: Link to AWS S3 pricing -->

### TGZ archives

When an Artifact is uploaded, all the files are assembled into an immutable TGZ archive. There is currently no way to download artifacts in a format other than a TGZ or to download individual artifact contents.

## Where does the upload go?

At the bottom of the workflow summary page, there is a dedicated section for artifacts. Here's a screenshot of something you might see:

<!-- TODO: Update screenshot >
<img src="https://user-images.githubusercontent.com/16109154/103645952-223c6880-4f59-11eb-8268-8dca6937b5f9.png" width="700" height="300">

The size of the artifact is denoted in bytes. The displayed artifact size denotes the size of the zip that `upload-artifact` creates during upload.