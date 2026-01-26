#!/usr/bin/env fish

# NTFS Auto-Mount Script
# Automatically mounts NTFS partitions with Windows-style naming

function get_next_drive_letter
    set -l letters C D E F G H I J K L M N O P Q R S T U V W X Y Z
    set -l used_letters

    # Get already used drive letters from mount points
    for dir in /mnt/Win-*
        if test -d $dir
            set -l letter (string replace '/mnt/Win-' '' $dir)
            set -a used_letters $letter
        end
    end

    # Find first unused letter
    for letter in $letters
        if not contains $letter $used_letters
            echo $letter
            return 0
        end
    end

    echo Z # Fallback
end

function main
    echo "=== NTFS Partition Auto-Mount Script ==="
    echo ""

    # Check if ntfs-3g is installed
    if not command -v mount.ntfs-3g >/dev/null
        echo "❌ ERROR: ntfs-3g is not installed!"
        echo ""
        echo "Please install it first:"
        echo "  Debian/Ubuntu: sudo apt install ntfs-3g"
        echo "  Arch/Manjaro:  sudo pacman -S ntfs-3g"
        echo "  Fedora/RHEL:   sudo dnf install ntfs-3g"
        return 1
    end

    # Backup fstab
    set -l timestamp (date +%Y%m%d_%H%M%S)
    set -l backup_file "/etc/fstab.backup.$timestamp"

    echo "📦 Backing up /etc/fstab to $backup_file"
    sudo cp /etc/fstab $backup_file
    if test $status -eq 0
        echo "✅ Backup created successfully"
    else
        echo "❌ Backup failed! Exiting."
        return 1
    end
    echo ""

    # Get NTFS partitions
    set -l partitions (lsblk --filter 'FSTYPE=="ntfs"' --output 'NAME,UUID,LABEL' -r | tail -n +2)

    if test -z "$partitions"
        echo "ℹ️  No NTFS partitions found."
        return 0
    end

    set -l added_count 0
    set -l skipped_count 0
    set -l mounted_count 0

    echo "🔍 Processing NTFS partitions..."
    echo ""

    for line in $partitions
        set -l parts (string split ' ' $line)
        set -l name $parts[1]
        set -l uuid $parts[2]
        set -l label $parts[3]

        # Determine mount point name
        set -l mount_name
        if test -n "$label"; and test "$label" != NAME
            set mount_name "Win-$label"
        else
            set -l drive_letter (get_next_drive_letter)
            set mount_name "Win-$drive_letter"
        end

        set -l mount_point "/mnt/$mount_name"

        # Check if already in fstab
        if grep -q "UUID=$uuid" /etc/fstab
            echo "⏭️  SKIPPED: $name (UUID=$uuid)"
            echo "   Already exists in fstab"
            echo "   Mount point: $mount_point"
            set skipped_count (math $skipped_count + 1)
        else
            echo "➕ ADDING: $name (UUID=$uuid)"
            if test -n "$label"; and test "$label" != NAME
                echo "   Label: $label"
            else
                echo "   Label: (none)"
            end
            echo "   Mount point: $mount_point"

            # Create mount point if it doesn't exist
            if not test -d $mount_point
                sudo mkdir -p $mount_point
                echo "   📁 Created directory: $mount_point"
            end

            # Add to fstab with proper quoting
            set -l fstab_entry "UUID=$uuid $mount_point ntfs-3g defaults,windows_names,uid=1000,gid=1000,umask=022 0 0"
            printf '%s\n' "$fstab_entry" | sudo tee -a /etc/fstab >/dev/null
            echo "   ✅ Added to /etc/fstab"

            # Mount the partition
            sudo mount "$mount_point" 2>/dev/null
            if test $status -eq 0
                echo "   🎉 Mounted successfully"
                set mounted_count (math $mounted_count + 1)
            else
                echo "   ⚠️  Mount failed (will mount on next boot or run 'sudo mount -a')"
            end

            set added_count (math $added_count + 1)
        end
        echo ""
    end

    # Summary
    echo "================================"
    echo "📊 SUMMARY"
    echo "================================"
    echo "Partitions added:    $added_count"
    echo "Partitions skipped:  $skipped_count"
    echo "Partitions mounted:  $mounted_count"
    echo "Backup location:     $backup_file"
    echo ""

    if test $added_count -gt 0
        echo "✨ New partitions have been configured!"
        echo "💡 Run 'sudo mount -a' to mount all partitions"
        echo "   or reboot to ensure everything is mounted."
    else
        echo "ℹ️  No changes were made to fstab."
    end
end

# Run main function
main
