#! /usr/bin/perl -w
#
# Example of plugin module
# This is the API part of UsersPluginLDAPShadowAccount plugin
# - configuration of ShadowAccount object class of LDAP users
#
# For documentation and examples of function arguments and return values, see
# UsersPluginLDAPAll.pm

package UsersPluginLDAPShadowAccount;

use strict;

use YaST::YCP qw(:LOGGING);
use YaPI;
use Data::Dumper;

textdomain("users");

our %TYPEINFO;

##--------------------------------------
##--------------------- global imports

YaST::YCP::Import ("Ldap");
YaST::YCP::Import ("SCR");
YaST::YCP::Import ("UsersLDAP");

##--------------------------------------
##--------------------- global variables

# object classes handled by this plugin
my $user_object_class			= "shadowaccount";

# conflicting plugin name
my $pwdpolicy_plugin			= "UsersPluginLDAPPasswordPolicy";

# error message, returned when some plugin function fails
my $error	= "";

# internal name
my $name	= "UsersPluginLDAPShadowAccount";

##----------------------------------------
##--------------------- internal functions

# check if given key (second parameter) is contained in a list (1st parameter)
# if 3rd parameter is true (>0), ignore case
sub contains {
    my ($list, $key, $ignorecase) = @_;
    if (!defined $list || ref ($list) ne "ARRAY" || @{$list} == 0) {
	return 0;
    }
    if ($ignorecase) {
        if ( grep /^\Q$key\E$/i, @{$list} ) {
            return 1;
        }
    } else {
        if ( grep /^\Q$key\E$/, @{$list} ) {
            return 1;
        }
    }
    return 0;
}

# provide current value for shadowlastchange attribute
sub last_change_is_now {

    my %out = %{SCR->Execute (".target.bash_output", "date +%s")};
    my $seconds = $out{"stdout"} || "0";
    chomp $seconds;
    return sprintf ("%u", $seconds / (60*60*24));
}

# update the list of current object classes when adding plugin
sub update_object_classes {

    my ($config, $data)	= @_;

    if (defined $data->{"objectclass"} && ref $data->{"objectclass"} eq "ARRAY")
    {
	my @orig_object_class	= @{$data->{"objectclass"}};
	if (!contains (\@orig_object_class, $user_object_class, 1)) {
	    push @orig_object_class, $user_object_class;
	    $data->{"objectclass"}	= \@orig_object_class;
	}
	# set default values for new variables
	my $shadow	= UsersLDAP->GetDefaultShadow ();
	foreach my $attr (keys %$shadow) {
	    if (!defined $data->{$attr} || $data->{$attr} eq "") {
		$data->{$attr}  = $shadow->{$attr};
	    }
	}
	if (!defined $data->{"shadowlastchange"}) {
	    $data->{"shadowlastchange"} = last_change_is_now ();
	}
    }
    return $data;
}

# update the object data when removing plugin
sub remove_plugin_data {

    my ($config, $data) = @_;
    my @updated_oc;
    foreach my $oc (@{$data->{'objectclass'}}) {
        if (lc($oc) ne $user_object_class) {
            push @updated_oc, $oc;
        }
    }
    $data->{'objectclass'} = \@updated_oc;
    foreach my $attr ("shadowinactive", "shadowexpire", "shadowlastchange",
            "shadowmin", "shadowmax", "shadowwarning", "shadowflag")
    {
	$data->{$attr}  = "";
    }
    return $data;
}

##------------------------------------------
##--------------------- global API functions

# return names of provided functions
BEGIN { $TYPEINFO{Interface} = ["function", ["list", "string"], "any", "any"];}
sub Interface {

    my $self		= shift;
    my @interface 	= (
	    "GUIClient",
	    "Check",
	    "Name",
	    "Summary",
	    "Restriction",
	    "WriteBefore",
	    "Write",
	    "AddBefore",
	    "Add",
	    "EditBefore",
	    "Edit",
	    "Interface",
	    "Disable",
	    "Enable",
	    "PluginPresent",
	    "PluginRemovable",
	    "Error",
    );
    return \@interface;
}

# return error message, generated by plugin
BEGIN { $TYPEINFO{Error} = ["function", "string", "any", "any"];}
sub Error {

    return $error;
}


# return plugin name, used for GUI (translated)
BEGIN { $TYPEINFO{Name} = ["function", "string", "any", "any"];}
sub Name {

    # plugin name
    return __("Shadow Account Configuration");
}

##------------------------------------
# return plugin summary (to be shown in table with all plugins)
BEGIN { $TYPEINFO{Summary} = ["function", "string", "any", "any"];}
sub Summary {

    # user plugin summary (table item)
    return __("Edit Shadow Account attributes");
}

##------------------------------------
# checks the current data map of user (2nd parameter) and returns
# true if given user has our plugin
BEGIN { $TYPEINFO{PluginPresent} = ["function", "boolean", "any", "any"];}
sub PluginPresent {

    my ($self, $config, $data)	= @_;

    if (contains ($data->{'objectclass'}, $user_object_class, 1)) {
	y2milestone ("LDAPShadowAccount plugin present");
	return 1;
    } else {
	y2debug ("LDAPShadowAccount plugin not present");
	return 0;
    }
}

##------------------------------------
# Is it possible to remove this plugin from user?
BEGIN { $TYPEINFO{PluginRemovable} = ["function", "boolean", "any", "any"];}
sub PluginRemovable {

    return YaST::YCP::Boolean (1);
}


##------------------------------------
# return name of YCP client defining YCP GUI
BEGIN { $TYPEINFO{GUIClient} = ["function", "string", "any", "any"];}
sub GUIClient {

    return "users_plugin_ldap_shadowaccount";
}

##------------------------------------
# Type of objects this plugin is restricted to.
# Plugin is restricted to LDAP users
BEGIN { $TYPEINFO{Restriction} = ["function",
    ["map", "string", "any"], "any", "any"];}
sub Restriction {

    return {
	    "ldap"	=> 1,
	    "user"	=> 1
    };
}


##------------------------------------
# check if all required atributes of LDAP entry are present
# parameter is (whole) map of user
# return error message
BEGIN { $TYPEINFO{Check} = ["function",
    "string",
    "any",
    "any"];
}
sub Check {

    my ($self, $config, $data)	= @_;
    
    # attribute conversion
    my @required_attrs		= ();
    my @object_classes		= ();
    if (defined $data->{"objectclass"} && ref $data->{"objectclass"} eq "ARRAY")
    {
	@object_classes		= @{$data->{"objectclass"}};
    }

    # get the attributes required for entry's object classes
    foreach my $class (@object_classes) {
	my $req = Ldap->GetRequiredAttributes ($class);
	if (defined $req && ref ($req) eq "ARRAY") {
	    foreach my $r (@{$req}) {
		if (!contains (\@required_attrs, $r, 1)) {
		    push @required_attrs, $r;
		}
	    }
	}
    }
    my $action		= $data->{"what"} || "";
    # check the presence of required attributes
    foreach my $req (@required_attrs) {
	my $attr	= lc ($req);
	my $val		= $data->{$attr};
	if (substr ($action, 0, 5) eq "edit_" && !defined $val) {
	    # when editing using YaPI, attribute dosn't have to be loaded
	    next;
	}
	if (!defined $val || $val eq "" || 
	    (ref ($val) eq "ARRAY" && 
		((@{$val} == 0) || (@{$val} == 1 && $val->[0] eq "")))) {
	    # error popup (user forgot to fill in some attributes)
	    return sprintf (__("The attribute '%s' is required for this object according
to its LDAP configuration, but it is currently empty."), $attr);
	}
    }
    return "";
}

# this will be called from Users::EnableUser
BEGIN { $TYPEINFO{Enable} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub Enable {

    my ($self, $config, $data)	= @_;
    my $pw	= $data->{"userpassword"};
    
    if ((defined $pw) && $pw =~ m/^\!/) {
	$pw	=~ s/^\!//;
	$data->{"userpassword"}	= $pw;
    }
    $data->{"shadowexpire"}	= "";
    y2debug ("Enable LDAPAll called");
    return $data;
}

# this will be called from Users::DisableUser
#    	set "shadowExpire" to "0",
#	set a "!" before the hash-value in the "userpassword"
BEGIN { $TYPEINFO{Disable} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub Disable {

    my ($self, $config, $data)	= @_;

    my $pw	= $data->{"userpassword"};
    
    if ((defined $pw) && $pw !~ m/^\!/) {
	$data->{"userpassword"}	= "!".$pw;
    }
    $data->{"shadowexpire"}	= 0;
    y2debug ("Disable LDAPAll called");
    return $data;
}


# this will be called at the beggining of Users::Add
# Could be called multiple times for one user!
BEGIN { $TYPEINFO{AddBefore} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub AddBefore {

    my ($self, $config, $data)	= @_;

    # conflict with PasswordPolicy plugin
    if (!contains ($data->{'plugins_to_remove'}, $name, 1) &&
	contains ($data->{'plugins'}, $pwdpolicy_plugin, 1))
    {
	# error popup
	$error  = __("It is not possible to add this plugin when
the plugin for Password Policy is in use.");
	return undef;
    }
    return $data;
}


# This will be called just after Users::Add - the data map probably contains
# the values which we could use to create new ones
# Could be called multiple times for one user!
BEGIN { $TYPEINFO{Add} = ["function", ["map", "string", "any"], "any", "any"];}
sub Add {

    my ($self, $config, $data)	= @_;
    if (contains ($data->{'plugins_to_remove'}, $name, 1)) {
	y2milestone ("removing plugin $name ...");
	$data	= remove_plugin_data ($config, $data);
    }
    else {
	$data	= update_object_classes ($config, $data);
    }
    return $data;
}

# this will be called at the beggining of Users::Edit
BEGIN { $TYPEINFO{EditBefore} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub EditBefore {

    my ($self, $config, $data)	= @_;
    # $data: only new data that will be copied to current user map
    # data of original user are saved as a submap of $config
    # data with key "org_data"

    # in $data hash, there could be "plugins_to_remove": list of plugins which
    # has to be removed from the user

    # conflict with PasswordPolicy plugin
    if (!contains ($data->{'plugins_to_remove'}, $name, 1) &&
	contains ($data->{'plugins'}, $pwdpolicy_plugin, 1))
    {
	# error popup
	$error  = __("It is not possible to add this plugin when
the plugin for Password Policy is in use.");
	return undef;
    }
    return $data;
}

# this will be called just after Users::Edit
BEGIN { $TYPEINFO{Edit} = ["function",
    ["map", "string", "any"],
    "any", "any"];
}
sub Edit {

    my ($self, $config, $data)	= @_;

    if (contains ($data->{'plugins_to_remove'}, $name, 1)) {
	y2milestone ("removing plugin $name ...");
	$data	= remove_plugin_data ($config, $data);
    }
    else {
	$data	= update_object_classes ($config, $data);
    }
    y2debug ("Edit LDAPAll called");
    return $data;
}



# what should be done before user is finally written to LDAP
BEGIN { $TYPEINFO{WriteBefore} = ["function", "boolean", "any", "any"];}
sub WriteBefore {

    y2debug ("WriteBefore LDAPAll called");
    return YaST::YCP::Boolean (1);
}

# what should be done after user is finally written to LDAP
BEGIN { $TYPEINFO{Write} = ["function", "boolean", "any", "any"];}
sub Write {

    y2debug ("Write LDAPAll called");
    return YaST::YCP::Boolean (1);
}
1
# EOF
