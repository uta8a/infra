provider "google" {
  region  = var.region
  zone    = var.zone
  project = var.project
}

# bucket postfix にランダムな文字列を付与する
resource "random_id" "bucket" {
  byte_length = 8
}

data "archive_file" "todo-app" {
  type        = "zip"
  source_dir  = var.path
  output_path = format("%s.zip", var.path)
}

# Cloud Resources

# ./generated_resources.tf に出力
import {
  id = var.firestore_database
  to = google_firestore_database.default
}

resource "google_storage_bucket" "todo-app" {
  name          = "todo-app-${random_id.bucket.hex}"
  location      = var.bucket_region
  storage_class = "STANDARD" # デフォルトのストレージクラス https://cloud.google.com/storage/docs/storage-classes?hl=ja
}

resource "google_storage_bucket_object" "todo-app" {
  name   = "functions.${data.archive_file.todo-app.output_md5}.zip"
  bucket = google_storage_bucket.todo-app.name
  source = data.archive_file.todo-app.output_path
}

resource "google_cloudfunctions2_function" "todo-app" {
  name        = "todo-app"
  location    = var.region
  description = "todo-app function"

  build_config {
    runtime     = "nodejs20"
    entry_point = "execute"
    source {
      storage_source {
        bucket = google_storage_bucket.todo-app.name
        object = google_storage_bucket_object.todo-app.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256M"
    timeout_seconds    = 60
    environment_variables = {
      LOG_EXECUTION_ID = "true" # plan時に毎回差分が出てしまうので書いておく
    }
  }
}

resource "google_cloud_run_service_iam_binding" "todo-app" {
  location = google_cloudfunctions2_function.todo-app.location
  service  = google_cloudfunctions2_function.todo-app.name
  role     = "roles/run.invoker"
  members  = [var.member]
}

output "function_uri" {
  value = google_cloudfunctions2_function.todo-app.service_config[0].uri
}
