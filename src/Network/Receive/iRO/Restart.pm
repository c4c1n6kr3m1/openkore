#########################################################################
#  OpenKore - Network subsystem
#  Copyright (c) 2006 OpenKore Team
#
#  This software is open source, licensed under the GNU General Public
#  License, version 2.
#  Basically, this means that you're allowed to modify and distribute
#  this software. However, if you distribute modified versions, you MUST
#  also distribute the source code.
#  See http://www.gnu.org/licenses/gpl.html for the full license.
#########################################################################
# Servertype overview: http://wiki.openkore.com/index.php/ServerType
package Network::Receive::iRO::Restart;

use strict;
use base qw(Network::Receive::iRO);
use Globals qw($questList %quests_lut %monsters_lut);
use Log qw(message debug);
use Translation qw(T TF);

sub quest_all_list3 {
	my ( $self, $args ) = @_;

	# Long quest lists are split up over multiple packets. Only reset the quest list if we've switched maps.
	our $quest_generation      ||= 0;
	our $last_quest_generation ||= 0;
	if ( $last_quest_generation != $quest_generation ) {
		$last_quest_generation = $quest_generation;
		$questList             = {};
	}

	my $i = 0;
	while ( $i < $args->{RAW_MSG_SIZE} - 8 ) {
		my ( $questID, $active, $time_start, $time, $mission_amount ) = unpack( 'V C V2 v', substr( $args->{message}, $i, 15 ) );
		$i += 15;

		$questList->{$questID}->{active} = $active;
		debug "$questID $active\n", "info";

		my $quest = \%{ $questList->{$questID} };
		$quest->{time_start}     = $time_start;
		$quest->{time}           = $time;
		$quest->{mission_amount} = $mission_amount;
		debug "$questID $time_start $time $mission_amount\n", "info";

		if ( $mission_amount > 0 ) {
			for ( my $j = 0 ; $j < $mission_amount ; $j++ ) {
				my ( $conditionID, $mobID, $count, $goal, $mobName ) = unpack( 'V x4 V x4 v2 Z24', substr( $args->{message}, $i, 44 ) );
				$i += 44;
				$quest->{conditionID_to_mobID}->{$conditionID} = $mobID;
				
				my $mission = \%{$quest->{missions}->{$mobID}};
				$mission->{mobID}       = $mobID;
				$mission->{count}       = $count;
				$mission->{goal}        = $goal;
				$mission->{mobName_org} = $mobName;
				$mission->{mobName}     = $monsters_lut{$mobID} || I18N::bytesToString( $mobName );
				debug "- $mobID $count / $goal $mobName\n", "info";
			}
		}
	}
}

sub quest_add {
	my ($self, $args) = @_;
	my $questID = $args->{questID};
	my $quest = \%{$questList->{$questID}};

	unless (%$quest) {
		message TF("Quest: %s has been added.\n", $quests_lut{$questID} ? "$quests_lut{$questID}{title} ($questID)" : $questID), "info";
	}

	my $pack = 'a0 V v Z24';
	$pack = 'V x4 V x4 v Z24' if $args->{switch} eq '09F9';
	my $pack_len = length pack $pack, ( 0 ) x 7;

	$quest->{time_start} = $args->{time_start};
	$quest->{time} = $args->{time};
	$quest->{active} = $args->{active};
	debug $self->{packet_list}{$args->{switch}}->[0] . " " . join(', ', @{$args}{@{$self->{packet_list}{$args->{switch}}->[2]}}) ."\n";
	my $o = 17;
	for (my $i = 0; $i < $args->{amount}; $i++) {
		my ( $conditionID, $mobID, $count, $mobName ) = unpack $pack, substr $args->{RAW_MSG}, $o + $i * $pack_len, $pack_len;
#		my $mission = \%{$quest->{missions}->{$conditionID || $mobID}};
		my $mission = \%{$quest->{missions}->{$mobID}};
		$quest->{conditionID_to_mobID}->{$conditionID} = $mobID if $conditionID;
		
		$mission->{mobID} = $mobID;
		$mission->{conditionID} = $conditionID;
		$mission->{count} = $count;
		$mission->{mobName} = $monsters_lut{$mobID} || I18N::bytesToString($mobName);
		Plugins::callHook('quest_mission_added', {
				questID => $questID,
				mobID => $mobID,
				count => $count
		});
		debug "- $mobID $count $mobName\n", "info";
	}
}

sub quest_update_mission_hunt {
	my ($self, $args) = @_;
   
	for (my $i = 0; $i < (($args->{len}-6)/12); $i++) {
		my ($questID, $conditionID, $goal, $count) = unpack('V2 v2', substr($args->{RAW_MSG}, 6+($i*12), 12));
		my $quest = \%{$questList->{$questID}};
		my $mobID = $quest->{conditionID_to_mobID}->{$conditionID};
		my $mission = \%{$quest->{missions}->{$mobID}};
		$mission->{goal} = $goal;
		$mission->{count} = $count;
		debug "- $questID $mobID $count $goal\n", "info";
		message TF("Quest [%s] - defeated [%s - %s] progress (%d/%d) \n",$quests_lut{$questID} ? "$questID - $quests_lut{$questID}{title}" : '$questID',  $monsters_lut{$mobID} || $questList->{$questID}{missions}{$mobID}->{mobName},$mobID, $count, $goal), "info";

	}
}

1;
