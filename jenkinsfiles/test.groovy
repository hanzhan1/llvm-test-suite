// Manages communication with github for reporting important status
// events. Relies on Github integration plugin https://github.com/jenkinsci/github-plugin
class GithubStatus {

    // Repository to send status e.g: '/username/repo'
    String Repository

    // Commit hash to send status e.g: `909b76f97e`
    String Commit_id

    // Build url send status e.g: `https://jenkins/build/123`
    String BUILD_URL

    // Set pending status for this pull request
    def setPending(script, String context_name, String result_status_when_set_commit_failure = "UNSTABLE") {
        this.setBuildStatusStep(script, context_name, "In Progress", "PENDING", result_status_when_set_commit_failure)
    }

    // Set failed status for this pull request
    def setFailed(script, String context_name, String result_status_when_set_commit_failure = "UNSTABLE") {
        this.setBuildStatusStep(script, context_name, "Complete", "FAILURE", result_status_when_set_commit_failure)
    }

    // Set success status for this pull request
    def setSuccess(script, String context_name, String result_status_when_set_commit_failure = "UNSTABLE") {
        this.setBuildStatusStep(script, context_name, "Complete", "SUCCESS", result_status_when_set_commit_failure)
    }

    // Manually set PR status via GitHub integration plugin. Manual status updates are needed
    // Due to pipeline stage retries not propagating updates back to Github automatically
    def setBuildStatusStep(script, String context_name, String message, String state, String result_status_when_set_commit_failure) {
        def commitContextName = context_name
        def build_url_secret = this.BUILD_URL.replace("icl-jenkins.sc", "llvm-ci")

        script.retry(4) {
            script.step([
                    $class             : "GitHubCommitStatusSetter",
                    reposSource        : [$class: "ManuallyEnteredRepositorySource", url: "https://github.com/${this.Repository}"],
                    contextSource      : [$class: "ManuallyEnteredCommitContextSource", context: commitContextName],
                    errorHandlers      : [],
                    commitShaSource    : [$class: "ManuallyEnteredShaSource", sha: this.Commit_id],
                    //statusBackrefSource: [$class: "ManuallyEnteredBackrefSource", backref: "${this.BUILD_URL}flowGraphTable/"],
                    statusBackrefSource: [$class: "ManuallyEnteredBackrefSource", backref: "${build_url_secret}"],
                    statusResultSource : [$class: "ConditionalStatusResultSource", results: [[$class: "AnyBuildResult", message: message, state: state]]]
            ])
        }


    }
}


def fill_task_name_description () {
    script {
        currentBuild.displayName = "PR#${env.PR_number}-No.${env.BUILD_NUMBER}"
        currentBuild.description = "PR number: ${env.PR_number} / Commit id: ${env.Commit_id}"
    }
}

def githubStatus = new GithubStatus(
        Repository: params.Repository,
        Commit_id: params.Commit_id,
        BUILD_URL: env.RUN_DISPLAY_URL
)


build_ok = true
fail_stage = ""
user_in_github_group = false

pipeline {

    agent { label "master" }
    options {
        durabilityHint 'PERFORMANCE_OPTIMIZED'
        timeout(time: 5, unit: 'HOURS')
        timestamps()
    }

    environment {
        def NUMBER = sh(script: "expr ${env.BUILD_NUMBER}", returnStdout: true).trim()
        def TIMESTEMP = sh(script: "date +%s", returnStdout: true).trim()
        def DATESTEMP = sh(script: "date +\"%Y-%m-%d\"", returnStdout: true).trim()
    }

    parameters {
        string(name: 'Commit_id', defaultValue: 'None', description: '',)
        string(name: 'PR_number', defaultValue: 'None', description: '',)
        string(name: 'Repository', defaultValue: 'hanzhan1/llvm-test-suite', description: '',)
        string(name: 'User', defaultValue: 'hanzhan1', description: '',)
    }
    triggers {
        GenericTrigger(
                genericVariables: [
                        [key: 'Commit_id', value: '$.pull_request.head.sha', defaultValue: 'None'],
                        [key: 'PR_number', value: '$.number', defaultValue: 'None'],
                        [key: 'Repository', value: '$.pull_request.base.repo.full_name', defaultValue: 'None'],
                        [key: 'User', value: '$.pull_request.user.login', defaultValue: 'None'],
                        [key: 'action', value: '$.action', defaultValue: 'None']
                ],

                causeString: 'Triggered on $PR_number',

                token: 'llvm-test-suite-test-ci',

                printContributedVariables: true,
                printPostContent: true,

                silentResponse: false,

                regexpFilterText: '$action',
                regexpFilterExpression: '(opened|reopened|synchronize)'
        )
    }

    stages {
        stage('Check_User_in_Org') {
            agent {
                label "llvm-test-suite-ci"
            }
            steps {
                script {
                    try {
                        retry(2) {
                            echo 'test ok'
                            githubStatus.setPending(this, "Jenkins/pre_Check")
                        }
                    }
                    catch (e) {
                        fail_stage = fail_stage + "    " + "Check_User_in_Org"
                        user_in_github_group = false
                        echo "Exception occurred when check User:${env.User} in group. Will skip build this time"
                        sh script: "exit -1", label: "Set Failure"
                    }
                }
            }
        }
/*
        stage('RHEL_Check') {
            when {
                expression { user_in_github_group }
            }
            agent { label "Debug_RHEL" }
            stages {
                stage('Git-monorepo'){
                    steps {
                        script {
                            try {
                                retry(2) {
                                    githubStatus.setPending(this, "Jenkins/RHEL_Check")
                                    if (fileExists('./src')) {
                                        sh script: 'rm -rf src', label: "Remove Src Folder"
                                    }

                                    sh script: 'cp -rf /export/users/sys_bbsycl/src ./', label: "Copy src Folder"
                                    sh script: "cd ./src; git config --local --add remote.origin.fetch +refs/pull/${env.PR_number}/head:refs/remotes/origin/pr/${env.PR_number}", label: "Set Git Config"
                                    sh script: "cd ./src; git pull origin; git checkout ${env.Commit_id}", label: "Checkout Commit"
//                                    checkout changelog: false, poll: false, scm: [$class: 'GitSCM', branches: [[name: '${Commit_id}']], doGenerateSubmoduleConfigurations: false, extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'src'], [$class: 'CloneOption', timeout: 200]], submoduleCfg: [], userRemoteConfigs: [[credentialsId: '9d434875-1c6b-4745-924b-52ed38305a9f', url: 'https://github.com/bb-sycl/oneDPL.git']]]

                                    if (fileExists('./oneAPI-samples')) {
                                        sh script: 'rm -rf oneAPI-samples', label: "Remove oneAPI-samples Folder"

                                    }
//                                    checkout changelog: false, poll: false, scm: [$class: 'GitSCM', branches: [[name: 'master']], doGenerateSubmoduleConfigurations: false, extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'oneAPI-samples'], [$class: 'CloneOption', timeout: 200]], submoduleCfg: [], userRemoteConfigs: [[credentialsId: '9d434875-1c6b-4745-924b-52ed38305a9f', url: 'https://github.com/oneapi-src/oneAPI-samples.git']]]
                                    sh script: 'cp -rf /export/users/sys_bbsycl/oneAPI-samples ./', label: "Copy oneAPI-samples Folder"
                                    sh script: 'cd ./oneAPI-samples; git pull origin master', label: "Git Pull oneAPI-samples Folder"
                                }
                            }
                            catch (e) {
                                build_ok = false
                                fail_stage = fail_stage + "    " + "Git-monorepo"
                                sh script: "exit -1", label: "Set failure"
                            }
                        }
                    }
                }

                stage('Merge_with_HEAD'){
                    steps {
                        script {
                            try {
                                retry(2) {
                                    sh script: "cd ./src; git merge --ff release_oneDPL", label: "Merge with latest release_oneDPL branch"
                                }
                            }
                            catch (e) {
                                build_ok = false
                                fail_stage = fail_stage + "    " + "Merge_with_HEAD"
                                sh script: "exit -1", label: "Set failure"
                            }
                        }
                    }
                }

                stage('Check_pstl_testsuite'){
                    steps {
                        timeout(time: 2, unit: 'HOURS'){
                            script {
                                def results = []
                                try {

                                    dir("./src/test") {
                                        if (fileExists('./output')) {
                                            sh script: 'rm -rf ./output;', label: "Remove output Folder"
                                        }
                                        sh "mkdir output; cp /export/users/sys_bbsycl/Makefile ./"
                                        def tests = findFiles glob: 'pstl_testsuite/**/*pass.cpp'

                                        def failCount = 0
                                        def passCount = 0

                                        for ( x in tests ) {
                                            try {
                                                phase = "Build&Run"
                                                case_name = x.name.toString()
                                                case_name = case_name.substring(0, case_name.indexOf(".cpp"))

                                                sh script: """
                                                    echo "Build and Run: ${x.path}"
                                                    make pstl-${case_name}
                                                """, label: "${case_name} Test"

                                                passCount++
                                                results.add([name: case_name, pass: true, phase: phase])
                                            }
                                            catch (e) {
                                                failCount++
                                                results.add([name: case_name, pass: false, phase: phase])
                                            }
                                        }
                                        if (failCount > 0) {
                                            sh "exit -1"
                                        }
                                    }
                                }
                                catch(e) {
                                    build_ok = false
                                    fail_stage = fail_stage + "    " + "Check_Run"
                                    failed_cases = "Failed cases are: "
                                    results.each { item ->
                                        if (!item.pass) {
                                            failed_cases = failed_cases + "\n" + "${item.name}"
                                        }
                                    }
                                    catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                                        sh script: """
                                            echo "${failed_cases}"
                                            exit -1
                                        """, label: "Print Failed Cases"
                                    }
                                }
                            }
                        }
                    }
                }

                stage('Check_extensions_testsuite'){
                    steps {
                        timeout(time: 2, unit: 'HOURS'){
                            script {
                                def results = []
                                try {

                                    dir("./src/test") {
                                        if (fileExists('./output')) {
                                            sh script: 'rm -rf ./output;', label: "Remove output Folder"
                                        }
                                        sh "mkdir output; cp /export/users/sys_bbsycl/Makefile ./"
                                        def tests = findFiles glob: 'extensions_testsuite/**/*pass.cpp'

                                        def failCount = 0
                                        def passCount = 0

                                        for ( x in tests ) {
                                            try {
                                                phase = "Build&Run"
                                                case_name = x.name.toString()
                                                case_name = case_name.substring(0, case_name.indexOf(".cpp"))

                                                sh script: """
                                                    echo "Build and Run: ${x.path}"
                                                    make extensions-${case_name}
                                                """, label: "${case_name} Test"

                                                passCount++
                                                results.add([name: case_name, pass: true, phase: phase])
                                            }
                                            catch (e) {
                                                failCount++
                                                results.add([name: case_name, pass: false, phase: phase])
                                            }
                                        }
                                        if (failCount > 0) {
                                            sh "exit -1"
                                        }
                                    }
                                }
                                catch(e) {
                                    build_ok = false
                                    fail_stage = fail_stage + "    " + "Check_extensions_testsuite"
                                    failed_cases = "Failed cases are: "
                                    results.each { item ->
                                        if (!item.pass) {
                                            failed_cases = failed_cases + "\n" + "${item.name}"
                                        }
                                    }
                                    sh script: """
                                        echo "${failed_cases}"
                                        exit -1
                                    """, label: "Print Failed Cases"
                                }
                            }
                        }
                    }
                }

                stage('Check_Samples'){
                    steps {
                        timeout(time: 1, unit: 'HOURS'){
                            script {
                                try {
                                    def gamma_return_value = sh(
                                            script: """
                                                    cd oneAPI-samples/Libraries/oneDPL/gamma-correction/
                                                    mkdir build
                                                    cd build/
                                                    cmake ..
                                                    make
                                                    make run
                                                    exit \$?""",
                                            returnStatus: true, label: "gamma_return_value Step")
                                    def stable_sort_return_value = sh(
                                            script: """
                                                    cd oneAPI-samples/Libraries/oneDPL/stable_sort_by_key/
                                                    mkdir build
                                                    cd build/
                                                    cmake ..
                                                    make
                                                    make run
                                                    exit \$?""",
                                            returnStatus: true, label: "stable_sort_return_value Step")

                                    if (gamma_return_value != 0 || stable_sort_return_value !=0) {
                                        echo "gamma-correction or stable_sort_by_key check failed. Please check log to fix the issue."
                                        sh script: "exit -1", label: "Set failure"
                                    }

                                }
                                catch(e) {
                                    build_ok = false
                                    fail_stage = fail_stage + "    " + "Check_Samples"
                                    catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                                        sh "exit -1"
                                    }
                                }
                            }
                        }
                    }
                }

            }

        }*/
    }

    post {
        always {
            script {
                if (build_ok) {
                        currentBuild.result = "SUCCESS"
                        githubStatus.setSuccess(this, "Jenkins/pre_Check")
                    } else {
                        currentBuild.result = "FAILURE"
                        githubStatus.setFailed(this, "Jenkins/pre_Check")
                    }
            }
        }
    }

}