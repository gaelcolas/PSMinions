Import-Module psMinions

# psMinions an asynchronous task queue/job queue based on distributed message passing, inspired from the Celery Python library: http://www.celeryproject.org/.
# It is focused on (near) real-time operation, and aims to provide the base for futher feature implementation (closer to the more mature Celery for python).
# The execution units, called tasks, are executed concurrently on a single or more worker servers using PSJobs. 
# Tasks can execute asynchronously (in the background) or synchronously (wait until ready).

#Design Ideas
# Scheduling: RabbitMQ has a plugin for Delayed Message (it's actually a new type of Exchange that accepts optional Delayed message). PSRabbitMQ needs to support the added header
#             A Scheduling Queue can be used and then Get-RabbitMQMessage, with filter on Execution time, ack only the ones that are ready to execute
#             Have a separate Interface for scheduled jobs. Then the Scheduled Interface, when idle, poll for job
#
# Tasks: The Task Definition can be a Psm1 (module) file, where exported functions are tasks
# 
# DSC: The worker instances should have a DSC Resource to configure them on different nodes (needs idempotence in module)
#
# Retries: The same principle than Celery can be used for task retry: http://docs.celeryproject.org/en/master/userguide/tasks.html#retrying
#
#

$psMinionsModuleConfigParams = @{
 Name = 'MyProject'
 broker = 'amqp://rabbitmq.server.my:'
 backend = ''
 include = 'tasks.ps1'
 psMinionsConfig= @{
  TASK_RESULT_TTL = '01:00:00:00.000'
  START = $false
 }

}

Set-psMinionsModuleConfig @psMinionsModuleConfigParams


$psMinionsWorkerParams = @{
 computerName = '',''
 concurrency = '4' #default to # of physical cores
 broker = ''
 app = ''
 queues = '',''
 TTL = '01:00:00:00.000'
 taskModule = './task.psm1'
}
#Feature list, support PSJob/runspaces

Start-psCeleryWorker $psMinionsWorkerParams