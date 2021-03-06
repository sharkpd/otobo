# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2020 Rother OSS GmbH, https://otobo.de/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --


package Kernel::System::AuthSession;

use strict;
use warnings;

use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
    'Kernel::System::Main',
    'Kernel::System::SystemData',
    'Kernel::System::SysConfig',
);

=head1 NAME

Kernel::System::AuthSession - global session interface

=head1 DESCRIPTION

All session functions.

=head1 PUBLIC INTERFACE

=head2 new()

Don't use the constructor directly, use the ObjectManager instead:

    my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get configured session backend
    my $GenericModule = $Kernel::OM->Get('Kernel::Config')->Get('SessionModule');
    $GenericModule ||= 'Kernel::System::AuthSession::DB';

    # get main object
    my $MainObject = $Kernel::OM->Get('Kernel::System::Main');

    # load session backend module
    if ( !$MainObject->Require($GenericModule) ) {
        $MainObject->Die("Can't load backend module $GenericModule! $@");
    }

    $Self->{Backend} = $GenericModule->new();

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    for my $SessionLimitConfigKey (
        qw(CustomerSessionLimit CustomerSessionPerUserLimit)
        )
    {
        $Self->{$SessionLimitConfigKey} = $ConfigObject->Get($SessionLimitConfigKey);
    }

    return $Self;
}

=head2 CheckSessionID()

checks a session, returns true (session ok) or false (session invalid)

    my $Ok = $SessionObject->CheckSessionID(
        SessionID => '1234567890123456',
    );

=cut

sub CheckSessionID {
    my ( $Self, %Param ) = @_;

    return $Self->{Backend}->CheckSessionID(%Param);
}

=head2 SessionIDErrorMessage()

returns an error in the session handling

    my $Message = $SessionObject->SessionIDErrorMessage();

=cut

sub SessionIDErrorMessage {
    my ( $Self, %Param ) = @_;

    return $Self->{SessionIDErrorMessage} || $Self->{Backend}->SessionIDErrorMessage(%Param);
}

=head2 GetSessionIDData()

get session data in a hash

    my %Data = $SessionObject->GetSessionIDData(
        SessionID => '1234567890123456',
    );

Returns:

    %Data = (
        UserSessionStart    => '1293801801',
        UserRemoteAddr      => '127.0.0.1',
        UserRemoteUserAgent => 'Some User Agent x.x',
        UserLastname        => 'SomeLastName',
        UserFirstname       => 'SomeFirstname',
        # and all other preferences values
    );

=cut

sub GetSessionIDData {
    my ( $Self, %Param ) = @_;

    return $Self->{Backend}->GetSessionIDData(%Param);
}

=head2 CreateSessionID()

create a new session with given data

    my $SessionID = $SessionObject->CreateSessionID(
        UserLogin => 'root',
        UserEmail => 'root@example.com',
    );

=cut

sub CreateSessionID {
    my ( $Self, %Param ) = @_;

    if ( !$Param{UserType} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got no UserType!'
        );
        return;
    }

    if ( $Param{UserType} ne 'User' && $Param{UserType} ne 'Customer' ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got wrong UserType!'
        );
        return;
    }

    return $Self->{Backend}->CreateSessionID(%Param);
}

=head2 RemoveSessionID()

removes a session and returns true (session deleted), false (if
session can't get deleted)

    $SessionObject->RemoveSessionID(SessionID => '1234567890123456');

=cut

sub RemoveSessionID {
    my ( $Self, %Param ) = @_;

    return $Self->{Backend}->RemoveSessionID(%Param);
}

=head2 UpdateSessionID()

update session info by key and value, returns true (if ok) and
false (if can't update)

    $SessionObject->UpdateSessionID(
        SessionID => '1234567890123456',
        Key       => 'LastScreenOverview',
        Value     => 'SomeInfo',
    );

=cut

sub UpdateSessionID {
    my ( $Self, %Param ) = @_;

    if ( $Param{Key} ) {

        my @Parts = split /:/, $Param{Key};

        if ( defined $Parts[1] ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Can't update key: '$Param{Key}' because ':' is not allowed!",
            );
            return;
        }
    }

    return $Self->{Backend}->UpdateSessionID(%Param);
}

=head2 GetExpiredSessionIDs()

returns a array of an array of session ids that have expired,
and one array of session ids that have been idle for too long.

    my @Sessions = $SessionObject->GetExpiredSessionIDs();

    my @ExpiredSession = @{$Session[0]};
    my @ExpiredIdle    = @{$Session[1]};

=cut

sub GetExpiredSessionIDs {
    my ( $Self, %Param ) = @_;

    return $Self->{Backend}->GetExpiredSessionIDs(%Param);
}

=head2 GetAllSessionIDs()

returns an array with all session ids

    my @Sessions = $SessionObject->GetAllSessionIDs();

=cut

sub GetAllSessionIDs {
    my ( $Self, %Param ) = @_;

    return $Self->{Backend}->GetAllSessionIDs(%Param);
}

=head2 GetActiveSessions()

Get the current active sessions for the given UserType.

    my %Result = $SessionObject->GetActiveSessions(
        UserType => '(User|Customer)',
    );

returns

    %Result = (
        Total => 8,
        PerUser => {
            UserID1 => 2,
            UserID2 => 1,
        },
    );

=cut

sub GetActiveSessions {
    my ( $Self, %Param ) = @_;

    if ( !$Param{UserType} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got no UserType!'
        );
        return;
    }

    if ( $Param{UserType} ne 'User' && $Param{UserType} ne 'Customer' ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Got wrong UserType!'
        );
        return;
    }

    return $Self->{Backend}->GetActiveSessions(%Param);
}

=head2 CleanUp()

clean-up of sessions in your system

    $SessionObject->CleanUp();

=cut

sub CleanUp {
    my ( $Self, %Param ) = @_;

    return $Self->{Backend}->CleanUp(%Param);
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTOBO project (L<https://otobo.de/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see L<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut
