package Amazon::SNS::V4;

use strict;
use warnings;

use base qw/ Class::Accessor::Fast /;

__PACKAGE__->mk_accessors(qw/ key secret error status_code service debug signer error_response/);

use LWP::UserAgent;
use XML::Simple;
use URI::Escape;
use AWS::Signature4;
use HTTP::Request::Common;
use Amazon::SNS::V4::Target;
use Amazon::SNS::V4::Topic;

our $VERSION = '1.9';


sub CreateTopic
{
	my ($self, $name) = @_;

	my $r = $self->dispatch({
		'Action'	=> 'CreateTopic',
		'Name'		=> $name,
	});

	my $arn = eval { $r->{'CreateTopicResult'}{'TopicArn'} };

	return defined $arn ? $self->GetTopic($arn) : undef;
}

sub GetTopic
{
	my ($self, $arn) = @_;

	return Amazon::SNS::V4::Topic->new({
		'sns' => $self,
		'arn' => $arn,
	});
}

sub GetTarget
{
	my ($self, $arn) = @_;

	return Amazon::SNS::V4::Target->new({
		'sns' => $self,
		'arn' => $arn,
	});
}

sub DeleteTopic
{
	my ($self, $arn) = @_;

	return $self->dispatch({
		'Action'	=> 'DeleteTopic',
		'TopicArn'	=> $arn,
	});
}

sub ListTopics
{
	my ($self, $name) = @_;

	my $r = $self->dispatch({
		'Action'	=> 'ListTopics',
	});

	return map {

		Amazon::SNS::V4::Topic->new({
			'sns' => $self,
			'arn' => $_->{'TopicArn'},
		})

	} @{$r->{'ListTopicsResult'}{'Topics'}[0]{'member'}};
}

sub Subscribe
{
	my ($self, $protocol, $topicarn, $endpoint) = @_;

	$self->dispatch({
		'Action'	=> 'Subscribe',
		'Protocol'	=> $protocol,
		'TopicArn'	=> $topicarn,
		'Endpoint'	=> $endpoint,
	});
}

sub Unsubscribe
{
	my ($self, $arn) = @_;

	$self->dispatch({
		'Action'		=> 'Unsubscribe',
		'SubscriptionArn'	=> $arn,
	});
}

sub dispatch
{
	my ($self, $args) = @_;

	$self->error(undef);
	$self->error_response(undef);

	$self->service('http://sns.eu-west-1.amazonaws.com')
		unless defined $self->service;
	$self->signer( AWS::Signature4->new(
		-access_key => scalar $self->key,
		-secret_key => scalar $self->secret,
	)) unless defined $self->signer;
	my $signer = $self->signer;

	# sanitize args
	do { delete $args->{$_} unless defined $args->{$_} } for (keys %$args);

	$args->{'Version'} = '2010-03-31';

	if (defined($args->{'Attributes'}) and ref($args->{'Attributes'}) eq 'HASH') {
		foreach my $attr (keys %{$args->{'Attributes'}}) {
			$args->{$attr} = $args->{'Attributes'}->{$attr};
		}
		delete $args->{'Attributes'};
	}

	my $post = POST $self->service, [%$args];
	$signer->sign( $post );
	
	my $response = LWP::UserAgent->new->request( $post );

	$self->status_code($response->code);

	if ($response->is_success) {
		return XMLin($response->content,
				'SuppressEmpty' => 1,
#				'KeyAttr' => { },
				'ForceArray' => [ qw/ Topics member / ],
		);
	} else {
		$self->error_response( $response_content );
		$self->error(
			($response->content =~ /^<.+>/)
				? eval { XMLin($response->content)->{'Error'}{'Message'} || $response->status_line }
				: $response->status_line
		);
	}

	print STDERR 'ERROR: ', $self->error, "\n"
		if $self->debug;

	return undef;
}

sub timestamp {

	return sprintf("%04d-%02d-%02dT%02d:%02d:%02d.000Z", sub {
		($_[5]+1900, $_[4]+1, $_[3], $_[2], $_[1], $_[0])
	}->(gmtime(time)));
}


1;

=pod

=head1 NAME

Amazon::SNS::V4 - Amazon Simple Notification Service with v4 Signatures

=head1 SYNOPSIS

  use Amazon::SNS::V4;

  my $sns = Amazon::SNS::V4->new({ 'key' => '...', 'secret' => '...' });


  # create a new topic and publish

  my $topic = $sns->CreateTopic('MyTopic')
	or die $sns->error;

  $topic->Publish('My test message');


  # delete it!

  $topic->DeleteTopic;


  # publish to a known ARN

  my $topic = $sns->GetTopic('arn:aws:sns:eu-west-1:123456789099:MyTopic');

  $topic->Publish('My test message', 'My Subject');


  # get all topics

  my @topics = $sns->ListTopics;

  print $_->arn, "\n" for @topics;



  # change region

  $sns->service('http://sns.us-east-1.amazonaws.com');

=head1 DESCRIPTION

Amazon::SNS::V4 is basically L<Amazon::SNS> v1.3, changed to use v4 Signatures, from
L<< AWS::Signature4 >>.

Sorry for not providing a better documentation, patches are always accepted. ;)

=head1 METHODS

=over

=item Amazon::SNS::V4->new({ 'key' => '...', 'secret' => '...' })

	Creates an Amazon::SNS::V4 object with given key and secret.

=item $sns->GetTopic($arn)

	Gives you an Amazon::SNS::V4::Topic object using an existing ARN.

=item $sns->GetTarget($arn)

	Gives you an Amazon::SNS::V4::Target object using an existing ARN. Sending Notification to TargetArn instead of TopicArn.

=item $sns->Publish($message, $subject, $attributes) (Amazon::SNS::V4::Target)

	When used with Amazon::SNS::V4::Target object (see GetTarget), additional parameter $attributes is used to pass 
	MessageAttributes.entry.N attributes with message.
	An example of MobilePush TTL: $attributes = {"AWS.SNS.MOBILE.APNS.TTL" => {"Type" => "String", "Value" => 3600}};
	More information can be found on Amazon web site: http://docs.aws.amazon.com/sns/latest/dg/sns-ttl.html

=item $sns->CreateTopic($name)

	Gives you an Amazon::SNS::V4::Topic object with the given name, creating it 
	if it does not already exist in your Amazon SNS account.

=item $sns->DeleteTopic($arn)

	Deletes a topic using its ARN.

=item $sns->ListTopics

	The result is a list of all the topics in your account, as an array of Amazon::SNS::V4::Topic objects.

=item $sns->error

	Description of the last error, or undef if none.

=item $sns->status_code

	The status code of the last HTTP response.

=back

=head1 ATTRIBUTES

=over

=item $sns->service

=item $sns->service($service_url)

	Get/set SNS service url, something like 'http://sns.us-east-1.amazonaws.com'.

=item $sns->key

=item $sns->key('...')

	Get/set auth key.

=item $sns->secret

=item $sns->secret('...')

	Get/set secret.

=item $sns->debug

=item $sns->debug(1)

	Get/set debug level. When set to 1 you'll get some debug output on STDERR.

=back

=head1 NOTES

Be sure to use ARNs in the same region as you have set the service to.

The module defaults to the EU (Ireland) region.


=head1 AUTHOR

Alessandro Zummo, E<lt>a.zummo@towertech.itE<gt>

James Wright, E<lt>jwright@cpan.orgE<gt>

=head1 SEE ALSO

L<Amazon::SNS>

L<AWS::Signature4>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2020 James Wright

Copyright (C) 2011-15 Alessandro Zummo


This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License version 2 as
published by the Free Software Foundation.


=cut

