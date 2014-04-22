#!/bin/bash

#####################################################
# APACHE TOMCAT CONTROL SCRIPT
#  Author: Peter Wright
#
# (c) 2008-2014
#####################################################


# Prepend all system state-changing actions with the following:
PP=""

control_main() {
	local ACTION=$(basename "$1")

	if [ "$2" == "--help" ] ; then
		echo "Usage: control.sh OPTION"
		echo "  Options: start      Starts tomcat (killing previous instances)"
		echo "           debug      Starts tomcat in debug mode (killing previous instances)"
		echo "           stop       Stops tomcat normally"
		echo "           kill       Terminates tomcat with a SIGKILL"
		echo "           install    Installs the script (only needed once)"
		echo "           uninstall  Removes the script"
		echo "           status     Determines whether tomcat is running"
		echo "           pid        Outputs tomcat's process id"
		echo "           clean      Removes old logfiles from the log directory"
		echo ""
		echo "There are also shortcuts that may be used (stop.sh, start.sh, kill.sh, pid.sh, etc)"
		echo ""
		echo "(c) Peter Wright 2008-2014"
		exit 0
	fi

	local CATALINA_HOME="$(getCatalinaHome)"
	local CATALINA_PID="$CATALINA_HOME/.pid"
	local JAVA_HOME="$(getJavaHome)"
	local TOMCAT_USER="$(getTomcatUser)"
	
	if [ -z "$JAVA_HOME" ] ; then
		echo "Could not find Java!" >&2
		exit 5
	fi

	# Take this opportunity to fix permissions (if possible)
	resetPermissions

	# Become the tomcat user if not already
	if [ "$(id -un)" != "$TOMCAT_USER" ] ; then
		exec sudo -u $TOMCAT_USER "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}"
	fi
	
	# The control script allows the actual action to be specified as an argument
	if [ "$ACTION" = "control.sh" ] ; then
		control_main $(dirname "$1")/"${2}.sh" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}"
	fi


	# Get rid of the PID file if it shouldn't exist
	processPidFile

	# Determine which script we're running
	local TOMCAT_SCRIPT=shutdown.sh
	case $ACTION in
		"install.sh")
				if [ $(id -u) != "0" ] ; then
					if [ $(id -un) != "$TOMCAT_USER" ] ; then
						echo "Installation: this may be a complete (or partial) failure because you're $(id -un), not root or $TOMCAT_USER"
					fi
				fi

				echo "Searching for myself in $CATALINA_HOME/bin/control.sh..."
				if [ ! -f "$CATALINA_HOME/bin/control.sh" ] ; then
					echo "Not found. Issuing copy command"
					cp "$0" "$CATALINA_HOME/bin/control.sh"
				fi

				if [ ! -f "$CATALINA_HOME/bin/pid.sh" ] ; then
					echo "Creating symbolic links..."

					ln -s ./control.sh "$CATALINA_HOME/bin/start.sh"
					ln -s ./control.sh "$CATALINA_HOME/bin/stop.sh"
					ln -s ./control.sh "$CATALINA_HOME/bin/kill.sh"
					ln -s ./control.sh "$CATALINA_HOME/bin/pid.sh"
					ln -s ./control.sh "$CATALINA_HOME/bin/status.sh"
					ln -s ./control.sh "$CATALINA_HOME/bin/debug.sh"
					ln -s ./control.sh "$CATALINA_HOME/bin/uninstall.sh"
				fi

				if [ ! -f "$CATALINA_HOME/bin/.shutdown.sh" ] ; then
					echo "Moving tomcat's startup/shutdown scripts"
					mv "$CATALINA_HOME/bin/shutdown.sh" "$CATALINA_HOME/bin/.inner_shutdown.sh"
					mv "$CATALINA_HOME/bin/startup.sh" "$CATALINA_HOME/bin/.inner_startup.sh"

					rm -f $CATALINA_HOME/bin/*.bat
					rm -f $CATALINA_HOME/bin/*.exe
					rm -f $CATALINA_HOME/bin/*.cmd
				fi

				echo "Creating debug startup script"
				cat >"$CATALINA_HOME/bin/.inner_debug.sh" <<EOF
#!/bin/bash

./bin/catalina.sh jpda start
EOF

				chmod +x $CATALINA_HOME/bin/*.sh
				chmod +x "$CATALINA_HOME/bin/.inner_debug.sh"

				exit 0;
			;;
		"uninstall.sh")
				rm $CATALINA_HOME/bin/{start,stop,kill,pid,status,debug,uninstall}.sh

				mv "$CATALINA_HOME/bin/.inner_startup.sh" "$CATALINA_HOME/bin/startup.sh"
				mv "$CATALINA_HOME/bin/.inner_shutdown.sh" "$CATALINA_HOME/bin/shutdown.sh"

				rm "$CATALINA_HOME/bin/.inner_debug.sh"

				exit 0;
			;;
		"clean.sh")
				echo "Tidying up log directory."

				# This is a really hacky way of finding the rotated logs
				rm -f $CATALINA_HOME/logs/*{2012,2013,2014,2015}* 2>/dev/null

				# Remove large logfiles
				find "$CATALINA_HOME/logs" -size +2M -delete

				exit 0
			;;
		"debug.sh")
				TOMCAT_SCRIPT=.inner_debug.sh

				killTomcat
				
				local JAVA_OPTS="$(getJavaOpts)"
			;;
		"start.sh")
				TOMCAT_SCRIPT=.inner_startup.sh

				# Ensure tomcat's not running before we start it
				killTomcat
				
				local JAVA_OPTS="$(getJavaOpts)"
			;;
		"stop.sh")
				TOMCAT_SCRIPT=.inner_shutdown.sh
			;;
		"kill.sh")
				killTomcat
				exit 0
			;;
		"pid.sh")
				if [ -f "$CATALINA_PID" ] ; then
					echo $(cat "$CATALINA_PID")
					exit 0
				else
					exit -1
				fi
			;;
		"status.sh")
				if [ -f "$CATALINA_PID" ] ; then
					echo "Tomcat is running with PID: $(cat "$CATALINA_PID")"
				else
					echo "Tomcat isn't running"
				fi
				exit 0
			;;
		*)
				echo "Unknown action $ACTION"
				echo "    Supported actions: start.sh, stop.sh, kill.sh, pid.sh, status.sh, install.sh"
				exit -1
			;;
	esac



	cd "$CATALINA_HOME"

	local SUDO_CMD=""
	if [ $(id -un) != "$TOMCAT_USER" ] ; then
		SUDO_CMD="sudo -u $TOMCAT_USER"
	fi

	# Upon install we rename the startup and shutdown scripts; try deforming the script in the same way if it doesn't exist
	if [ ! -f "$CATALINA_HOME/bin/$TOMCAT_SCRIPT" ] ; then
		TOMCAT_SCRIPT=".inner_$TOMCAT_SCRIPT"
	fi

	$PP exec $SUDO_CMD env "CATALINA_PID=$CATALINA_PID" "JAVA_HOME=$JAVA_HOME" "CATALINA_HOME=$CATALINA_HOME" "JAVA_OPTS=$JAVA_OPTS" "$CATALINA_HOME/bin/$TOMCAT_SCRIPT"

	# Terminate if nobody calls us
	exit 0
}


#######################################################################################################################################
# SUPPORT FUNCTIONS BELOW THIS LINE
#######################################################################################################################################

isGNUStat() {
	# Ugly workaround: GNU stat supports --help, BSD stat does not
	
	stat --help 2>/dev/null >/dev/null
	if [ "$?" = "0" ] ; then
		echo 1
	else
		echo 0
	fi
}

# Prints the owner of a given file/directory
getOwner() {
	isgnu=$(isGNUStat)
	
	if [ "$isgnu" = "1" ] ; then
		stat -c%U "$1"
	else
		uid_of_owner="$(stat -f%u "$1")"
		id -P "$uid_of_owner" | cut -d':' -f1
	fi
}

# Prints the modify date of a given file/directory
getModify() {
	isgnu=$(isGNUStat)
	
	if [ "$isgnu" = "1" ] ; then
		stat -c%Y "$1"
	else
		stat -f%m "$1"
	fi
}

# Determines which user to run Tomcat as
getTomcatUser() {
	echo "$(getOwner "$(getCatalinaHome)")"
}

# Retrieves the Tomcat folder
getCatalinaHome() {
	cd "$(dirname "$0")/../"

	echo "$(pwd)"
}

getJavaOpts() {
	local CATALINA_HOME="$(getCatalinaHome)"
	local CONFIG_FILE="${CATALINA_HOME}/conf/tomcat.conf"
	
	if [ -e "$CONFIG_FILE" ] ; then
		readConfigValues "$CONFIG_FILE" "opts.*"
	fi
}

readConfigValue() {
	cat "$1" | grep "^$2=" | head -n1 | cut -d'=' -f2-
}

readConfigValues() {
	cat "$1" | grep "^$2=" | cut -d'=' -f2- | xargs echo
}

# Tests if the provided folder is a valid java location
is_valid_java_home() {
	if [ -z "$1" ] ; then
		return 1
	elif [ ! -e "$1/bin/java" ] ; then
		return 3
	else
		return 0
	fi
}

# Retrieves the Java folder
getJavaHome() {
	local CATALINA_HOME="$(getCatalinaHome)"
	local J_HOME=""
	
	# If possible, use the JVM path stored in tomcat/.java_home
	if [ -e "$CATALINA_HOME/.java_home" ] ; then
		J_HOME=$(cat "$CATALINA_HOME/.java_home")
		
		if is_valid_java_home "$J_HOME" ; then
			echo "$J_HOME"
			return
		else
			rm -f "$CATALINA_HOME/.java_home" 2>/dev/null
		fi
	fi

	# Fall back to searching for a JVM
	for J_HOME in "$JAVA_HOME" "/opt/java" "/usr" "/System/Library/Frameworks/JavaVM.framework/Versions/CurrentJDK/Home"
	do
		if is_valid_java_home "$J_HOME" ; then
			echo "$J_HOME" > "$CATALINA_HOME/.java_home" 2>/dev/null
			echo "$J_HOME"
			return
		fi
	done

	echo "I can't find your java folder (I tried \$JAVA_HOME and some common locations and looked to see what JVM was used the last time tomcat started." >&2
	echo "Sorry, I'm giving up: no JAVA_HOME specified" >&2
	exit 5
}

# Sets the appropriate permissions 
resetPermissions() {
	# If we're root take the opportunity to ensure everything's owned by the tomcat user
	if [ $(id -u) = "0" ] ; then
		$PP chown -f -R "$TOMCAT_USER" "$CATALINA_HOME"
	fi
}

# Removes the PID file if it's of the wrong date (or if the process isn't running anymore)
processPidFile() {	
	if [ -e "$CATALINA_PID" ] ; then
		# If the process isn't running, remove the PID file
		ps $(cat "$CATALINA_PID") >/dev/null 2>/dev/null
		
		if [ "$?" = "1" ] ; then
			$PP rm -f "$CATALINA_PID"
		fi
		
		if [ -e "$CATALINA_PID" ] ; then
			local PID_MODIFY="$(getModify "$CATALINA_PID")"
			local BOOT_TIME="$(getBootTime)"

			if [ -z "$PID_MODIFY" ] ; then
				PID_MODIFY="0"
			fi

			# Delete the PID file if it's older than BOOT_TIME
			if [ "$BOOT_TIME" -gt "$PID_MODIFY" ] ; then
				$PP rm -f "$CATALINA_PID"
			fi
		fi
	fi
}

# Retrieves the timestamp of the last system boot
getBootTime() {
	if [ -f /proc/stat ] ; then
		grep btime /proc/stat 2>/dev/null | cut -d" " -f2
	else
		osxboot=$(sysctl -a | grep "kern.boottime: { sec = " | cut -d'=' -f2 | cut -d' ' -f2 | cut -d',' -f1)
		if [ -z "$osxboot" ] ; then
			echo 0
		else
			echo $osxboot
		fi
	fi
}

# Kills tomcat (if possible)
killTomcat() {
	if [ -f "$CATALINA_PID" ] ; then
		$PP kill -9 "$(cat "$CATALINA_PID")"
		$PP rm -f "$CATALINA_HOME/.pid"
	fi
}


help() {
	echo ""
}

control_main $0 $*

echo "Fallback termination (should never reach here)"
exit 250
