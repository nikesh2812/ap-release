#!/usr/bin/perl 
=head
# ##################################
# Module : deploy
#
# SYNOPSIS
# This script to Publish the release Notes.
#
# Copyright 2015 eGovernments Foundation
#
#  Log
#  By          	Date        	Change
#  Vasanth KG  	04/02/2016	    Initial Version
#
# #######################################
=cut

# Add template folder to PAR file
# PAR Packager : pp -a template -M DBI -M JSON -M JIRA::REST -M pgDB.pm -M Utils.pm -M Crypt::CBC -M Crypt::Blowfish -M JSON -M Decrypt.pm -M DateTime -M Email.pm -M Common.pm --clean -o ap-release-notify ap-release.pl

# Package name
package release;

use strict;
use FindBin;
use lib "$FindBin::Bin";
use LWP;
#use LWP::UserAgent::ProgressBar;
#use Term::ProgressBar;
use JSON;
use Cwd;
use utf8;
use Encode;
#use MIME::Base64;
use Cwd 'abs_path';
use File::Tee qw(tee);
use File::Basename;
use File::Path qw(make_path remove_tree);
use HTML::Template;
use Common;
use Utils;
use Data::Dumper qw(Dumper);
use MIME::Base64;
use JIRA::REST;
use Net::SMTP::SSL;
#use XML::Simple;
use Crypt::CBC;
use MIME::Base64;
use Email;
use Decrypt;

use constant TRUE => 1;
use constant FALSE => 0;

use constant DATABASE 	=> "devops";

my $ACCOUNT_NAME = shift;
my $ENVIRONMENT = shift;
my $BUILD_NUMBER = shift;
my $AP_RELEASE_CARD = shift;

my ( $tenant_header, $SUBJECT, $STATUS, $par_template_dir, $search, $count,  @issueResults, $i, $tabale_header, $table_footer, @table_data, @td_data);

## PAR TEMP path to get the Template path
my $DEBUG = TRUE;
if ( $DEBUG == FALSE )
{
	$par_template_dir = "$ENV{PAR_TEMP}/inc/template";
}
else
{
	$par_template_dir = $FindBin::Bin."/template";
}

my $CURRENTTIMESTAMP = `date "+%Y-%m-%d %H:%M"`;
my $CURRENTDATE = `date "+%Y-%m-%d"`;

#---------------------------------------------------
#GET JENKINS BUILD DETAILS
#---------------------------------------------------
my $pgDB = Utils::getDBInstanceGivenDBName(DATABASE);
my $account_details = "select PRJ.name as prjname,PRJ.jira_key,PRJ.jira_user, PRJ.jira_password, PRJ.jira_url, PRJ.jenkins_url,
PRJ.jenkins_user, PRJ.jenkins_token, PRJ.jenkins_job, env.name as envname, env.status, PRJ.tenant, PRJ.is_rc_exists from account as AC, projects as PRJ, environment as env where AC.active=true AND PRJ.active=true AND AC.name='".$ACCOUNT_NAME."' AND AC.id=PRJ.account_id and env.name='".$ENVIRONMENT."' order by PRJ.id desc"; 
my @PROJECTS = $pgDB->selectQuery($account_details);
#last release date
my $lastrelease = "select lpr.last_deployed_date from last_prod_release as lpr, account as AC where AC.active=true AND AC.name='".$ACCOUNT_NAME."' AND AC.id=lpr.account_id";
my $lastRelease = $pgDB->selectQueryForRow($lastrelease);
my $account_id_query = "select id from account where active=true AND name='".$ACCOUNT_NAME."'";
my $account_id = $pgDB->selectQueryForRow($account_id_query);

if (@PROJECTS)
{
	#############################################
	my ($count, $ap_artifilename,$platform_artifilename,$ap_arti_version,$tenant_build,$tenant_version,$platform_build,$platform_version);
	foreach my $PROJECT (@PROJECTS)
	{
		### JIRA LOGIN
		my $jira = JIRA::REST->new($PROJECT->{jira_url}, $PROJECT->{jira_user}, $PROJECT->{jira_password});
		#TABLE HEADER
		 
		#my @issues_type_available = getIssuesTypes($pgDB);
		if ( $PROJECT->{is_rc_exists} eq TRUE )
		{
			$tabale_header = "<tr style='background:#ccc; background: -webkit-linear-gradient(left, rgba(220,213,213,1) 0%, rgba(222,222,222,0) 100%, rgba(222,222,222,0) 100%, rgba(222,222,222,1) 100%); 
    		background-attachment:fixed;border-bottom: 1px solid #ccc;'><td style='vertical-align: middle;' colspan='4'><h3><a href='".$PROJECT->{jira_url}."/browse/".$PROJECT->{jira_key}."'>".$PROJECT->{prjname}."</a></h3></td></tr>
<tr><th>Issue Key</th><th>Component Name</th><th>Description<th>Status</th></tr>";
			#AND resolution in (Fixed,Done)	
			$search = $jira->POST('/search', undef, {
		        jql        => 	'project = '.$PROJECT->{jira_key}.' AND status in ("AWAITING RELEASE") 
		        				AND "Fixed On" >= "'.$lastRelease->{last_deployed_date}.'" AND 
		        				"Fixed On" <= "'.$CURRENTTIMESTAMP.'" ORDER BY component ASC, type ASC, key DESC',
		        fields     => [ qw/summary status assignee/ ],
		    	});

			foreach my $APISSUE (@{$search->{issues}}) 
			{
				my @COMP;
				$count++;
				my $APIMPL_ISSUE_DETAILS = $jira->GET("/issue/".$APISSUE->{key});
				my $issue_summary = $APIMPL_ISSUE_DETAILS->{fields}->{summary};
				my $issue_type_iconUrl = $APIMPL_ISSUE_DETAILS->{fields}->{issuetype}->{iconUrl};
				my $issue_type = $APIMPL_ISSUE_DETAILS->{fields}->{issuetype}->{name};
				my $issue_status = $APIMPL_ISSUE_DETAILS->{fields}->{status}->{name};
				my $issue_status_iconUrl = $APIMPL_ISSUE_DETAILS->{fields}->{status}->{iconUrl};
				my $issue_reporter = $APIMPL_ISSUE_DETAILS->{fields}->{reporter}->{emailAddress};
				my $issue_assignee = $APIMPL_ISSUE_DETAILS->{fields}->{assignee}->{emailAddress};
				my $issue_created = $APIMPL_ISSUE_DETAILS->{fields}->{created};
				my $issue_updated = $APIMPL_ISSUE_DETAILS->{fields}->{updated};
				push @COMP, $_->{name} foreach @{$APIMPL_ISSUE_DETAILS->{fields}->{components}};
				my $COMP_NAME = join (",",@COMP);
				push (@td_data , '<tr style="border-bottom: 1px solid #ccc;"><td style="vertical-align: middle;"><img style="display:inline;vertical-align: middle;" src="'.$issue_type_iconUrl.'" /> <a href="'.$PROJECT->{jira_url}.'/browse/'.$APISSUE->{key}.'">'.$APISSUE->{key}.'</a></td><td style="vertical-align: middle;">'.$COMP_NAME.'</td><td style="vertical-align: middle;">'.$issue_summary.'</td><td><img style="display:inline;vertical-align: middle;" src="'.$issue_status_iconUrl.'" /> ' .$issue_status.'</td></tr>');
			}
		}

		if ( $PROJECT->{is_rc_exists} eq FALSE )
		{
			#CHECK TENANT BUILD DETAILS
			$STATUS = $PROJECT->{status};
			if ( $PROJECT->{tenant} eq TRUE )
			{
				my $JOB_CONTENT = decode_json(jenkinsAuthToken($PROJECT->{jenkins_user}, $PROJECT->{jenkins_token}, $PROJECT->{jenkins_url}, $BUILD_NUMBER));
				$ap_artifilename =  $_->{fileName} foreach @{($JOB_CONTENT->{artifacts})};
				$tenant_version = `echo $ap_artifilename | awk -F '-' '{print \$(NF-1)"-"\$(NF)}' | rev | cut -d. -f2- | rev`;
				$tenant_build = $JOB_CONTENT->{id};		
				foreach (@{$JOB_CONTENT->{actions}})
				{
						#print Dumper($_);
				        $platform_build = $_->{id} foreach @{($_->{triggeredBuilds})};
				        foreach (@{$_->{triggeredBuilds}})
				        {
				        	$platform_artifilename = $_->{fileName} foreach @{($_->{artifacts})};
				        	$platform_version = `echo $platform_artifilename | awk -F '-' '{print \$(NF-1)"-"\$(NF)}' | rev | cut -d. -f2- | rev`;
				        }
				}
				#print "PLATFORM - $platform_build - $platform_version";
				#exit 1;
			}
		   
		    $tabale_header = "<tr style='background:#ccc; background: -webkit-linear-gradient(left, rgba(220,213,213,1) 0%, rgba(222,222,222,0) 100%, rgba(222,222,222,0) 100%, rgba(222,222,222,1) 100%); 
    		background-attachment:fixed;border-bottom: 1px solid #ccc;'><td style='vertical-align: middle;' colspan='4'><h3><a href='".$PROJECT->{jira_url}."/browse/".$PROJECT->{jira_key}."'>".$PROJECT->{prjname}."</a></h3></td></tr>
<tr><th>Issue Key</th><th>Component Name</th><th>Description<th>Status</th></tr>";
		    # Iterate on issues
		if ( $PROJECT->{jira_key} eq "PHOENIX" )
		{ 
			$search = $jira->POST('/search', undef, { jql        => 'project = '.$PROJECT->{jira_key}.' AND status in (Resolved, Closed) AND component != "Building Plan" AND resolution not in (Invalid, Duplicate) AND (labels != ui-automation OR labels is EMPTY) AND resolution in (Fixed,Done) AND resolutiondate >= "'.$lastRelease->{last_deployed_date}.'" AND resolutiondate <= "'.$CURRENTTIMESTAMP.'" ORDER BY component ASC, type ASC, key DESC', fields     => [ qw/summary status assignee/ ], });
		}
		else
		{
			$search = $jira->POST('/search', undef, { jql        => 'project = '.$PROJECT->{jira_key}.' AND status in (Resolved, Closed) AND resolution not in (Invalid, Duplicate) AND (labels != ui-automation OR labels is EMPTY) AND resolution in (Fixed,Done) AND resolutiondate >= "'.$lastRelease->{last_deployed_date}.'" AND resolutiondate <= "'.$CURRENTTIMESTAMP.'" ORDER BY component ASC, type ASC, key DESC', fields     => [ qw/summary status assignee/ ], });
		}
			# Get issue
			foreach my $issue (@{$search->{issues}}) 
			 {
				my @COMP;
			 	$count++;
			    	my $issuedetails = $jira->GET("/issue/".$issue->{key});
			    	#print Dumper($issuedetails);
			    	my $issue_summary = $issuedetails->{fields}->{summary};
			    	#my $jira_resolutiondate = $issuedetails->{fields}->{resolutiondate};
				my $issue_type_iconUrl = $issuedetails->{fields}->{issuetype}->{iconUrl};
				my $issue_type = $issuedetails->{fields}->{issuetype}->{name};
				my $issue_status = $issuedetails->{fields}->{status}->{name};
				my $issue_status_iconUrl = $issuedetails->{fields}->{status}->{iconUrl};
				my $issue_reporter = $issuedetails->{fields}->{reporter}->{emailAddress};
				my $issue_assignee = $issuedetails->{fields}->{assignee}->{emailAddress};
				my $issue_created = $issuedetails->{fields}->{created};
				my $issue_updated = $issuedetails->{fields}->{updated};
				push @COMP, $_->{name} foreach @{$issuedetails->{fields}->{components}};
                                my $COMP_NAME = join (",",@COMP);
				#print "==> $issue->{key} - $issue_type - $issue_summary - $issue_reporter - $issue_created - $issue_assignee - $issue_updated - $issue_status\n";
				#print $issue->{key}.' - '. $issue_type;
				push (@td_data , '<tr style="border-bottom: 1px solid #ccc;">
				<td style="vertical-align: middle;"><img style="display:inline;vertical-align: middle;" src="'.$issue_type_iconUrl.'" /> <a href="'.$PROJECT->{jira_url}.'/browse/'.$issue->{key}.'">'.$issue->{key}.'</a></td>
				<td style="vertical-align: middle;">'.$COMP_NAME.'</td>
				<td style="vertical-align: middle;">'.$issue_summary.'</td>
				<td><img style="display:inline;vertical-align: middle;" src="'.$issue_status_iconUrl.'" /> ' .$issue_status.'</td></tr>');
	    	}
		}
		if ( scalar @td_data )
		{
					my $temp = join (" ", @td_data);
					@td_data = ();
					push (@table_data, $tabale_header.$temp);
		}
	}
	### Email
	my $mailWidget = '<div style="padding: 5px 10px;margin-left: 90px;"><div><span style="text-transform: uppercase;">AP@ '.$tenant_version.'</span>
		<span style="float:right;text-transform: uppercase;">Core@ '.$platform_version.'</span></div>
		<div ><span style="font-weight: bold;font-size: 18px;">BN #'.$tenant_build.'</span>
		<span style="float:right;font-weight: bold;font-size: 18px;">BN #'.$platform_build.'</span></div>
		<div style="background: rgba(0,0,0,0.2);margin: 5px -10px 5px -10px;height: 2px;border-radius: 0;">
		<div style="width: 100%;float: left;height: 100%;font-size: 12px;line-height: 20px;color: #fff;text-align: center;background-color: #fff;-webkit-box-shadow: inset 0 -1px 0 rgba(0,0,0,.15);box-shadow: inset 0 -1px 0 rgba(0,0,0,.15);-webkit-transition: width .6s ease;-o-transition: width .6s ease;transition: width .6s ease;-webkit-box-shadow: none;box-shadow: none;border-radius: 0;"></div>
		</div>
		<div><span style="font-size: 14px;white-space: nowrap;overflow: hidden;text-overflow: ellipsis;margin: 0;">
		'.$count.' Issues Fixed
		</span>
		<span style="float:right;font-size: 14px;white-space: nowrap;overflow: hidden;text-overflow: ellipsis;margin: 0;">
		'.$CURRENTTIMESTAMP.'
		</span></div>
		</div><!-- /.info-box-content -->';
	my $emailData = "<p>What's new in version ".$tenant_version." - #".$tenant_build."
		<table style='border:1px solid #ccc;' cellpadding='5' width='100%'>".join(" ",@table_data)."</table>";
	
	# Insert Deploy time Only for PROD
	if ($ENVIRONMENT eq "PROD")
	{
		$SUBJECT = '[ Release Notes for '.uc($ACCOUNT_NAME).' ]';
		#UPDATE latest prod release to DB
		$tenant_header = "Release Notes";
		updateLastReleaseData($pgDB, $account_id->{id}, $tenant_build, $tenant_version, $platform_build, $platform_version, $CURRENTTIMESTAMP );
	}
	else
	{
		$SUBJECT = '[ Pre Release Notes for '.uc($ACCOUNT_NAME).' ]';
		$tenant_header = "Pre Release Notes";
	}
	if ( $count )
	{
		Email::notify_release_notes($par_template_dir, $emailData, $mailWidget, $SUBJECT, $tenant_build, $tenant_version,$ENVIRONMENT, $tenant_header,$lastRelease->{last_deployed_date});
		#print Dumper ($mailWidget.$emailData);
	}
}

sub jenkinsAuthToken
{
        my ( $jenkinsUserName, $jenkinsToken, $JENKINS_JOB_URL, $buildnumber) = @_;
        my $uagent = LWP::UserAgent->new;
        #$logger->info("CI Authentication requested ...");
        my $req = HTTP::Request->new( GET => $JENKINS_JOB_URL."/".$buildnumber."/api/json?pretty=true&depth=2" );
        $req->header('content-type' => 'application/json');
        $req->authorization_basic($jenkinsUserName, $jenkinsToken);
        $uagent->ssl_opts( verify_hostname => 0 );
        my $response = $uagent->request($req);
        #($response->is_success) ? $logger->info('CI token authenticated successfully.') : ( $logger->error( "HTTP GET error code ". $response->code. " - ". $response->message."\n")
        #&& Email::notify_deployment_failure($logger,$TENANT_NAME,$par_template_dir,$baseConfigFile,$environment,"Jenkins auth failure : ". $response->code. " - ". $response->message,$buildnumber) && exit 1);
        return $response->decoded_content
}

sub getIssuesTypes
{
	my ( $pgDB ) = @_;
	my $query = "select name from issue_type order by id";
	my @issue_type = $pgDB->selectQuery($query);
	return @issue_type;
}

sub updateLastReleaseData
{
	my ( $pgDB, $account_id, $tenant_build_number, $tenant_version, $platform_build_number, $platform_version, $last_deployed_date ) = @_;
	my $query = "update last_prod_release set tenant_build_number='".$tenant_build_number."',
	tenant_version ='".$tenant_version."', 
	platform_build_number ='".$platform_build_number."',
	platform_version ='".$platform_version."',
	last_deployed_date = '".$last_deployed_date."' where account_id = '".$account_id."'";
	my $result = $pgDB->executeQuery($query);
	print "SUCCESS - Latest prod release Updated..!!" if ( $result );
}	

sub publish_ap_impl_tickets
{
	my($PROJECT,$ENVIRONMENT) = @_;
	
}
exit 0;

