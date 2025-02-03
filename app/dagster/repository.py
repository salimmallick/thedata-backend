from dagster import asset, AssetIn, Definitions, define_asset_job, ScheduleDefinition, repository

@asset
def sample_data():
    """A sample data asset that demonstrates Dagster functionality."""
    return {"status": "ok", "message": "Sample data asset is working"}

@asset(
    ins={"source_data": AssetIn(key="sample_data")}
)
def processed_data(source_data):
    """A sample processing asset that depends on sample_data."""
    return {
        "status": "processed",
        "source_status": source_data["status"],
        "message": f"Processed: {source_data['message']}"
    }

# Define a job that will materialize our assets
sample_job = define_asset_job(
    name="sample_job",
    selection=["sample_data", "processed_data"],
)

# Define a schedule for our job
sample_schedule = ScheduleDefinition(
    job=sample_job,
    cron_schedule="*/15 * * * *"  # Run every 15 minutes
)

@repository
def thedata_repository():
    """The main repository containing all Dagster assets, jobs, and schedules."""
    return [
        sample_data,
        processed_data,
        sample_job,
        sample_schedule
    ] 