locals {
  parsed_state_files = [
    for url in var.state_files : {
      bucket = regex("s3://([^/]+)/.*", url)[0]
      prefix = regex("s3://[^/]+/(.*)", url)[0]
    }
  ]

  grouped_by_bucket = {
    for obj in local.parsed_state_files : obj.bucket => compact([
      for obj2 in local.parsed_state_files : obj2.bucket == obj.bucket ? obj2.prefix : null
    ])...
  }

  image_uri = "237144093413.dkr.ecr.us-east-2.amazonaws.com/infracost/state-parser"
  image_arn = "arn:aws:ecr:us-east-2:237144093413:repository/infracost/cloudscraper"
}
