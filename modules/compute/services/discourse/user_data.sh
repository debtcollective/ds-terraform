#!/bin/bash
# Change SSH Port to 12345
perl -pi -e 's/^#?Port 22$/Port 12345/' /etc/ssh/sshd_config
service sshd restart || service ssh restart

# Add ssh keys for root user (/root/.ssh/authorized_keys)
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNmbm3AR92kE0igfVUJ9ZpY48oVS4Po+qH/3Jb6gF5NkHju+67Rf2MDkWQ4NzNp9yjlxL7LQk7c0dNuIR++GSS6dOLxixPXnLcYadqJF2h5qPV8RMNkOTuHR/zWPPEh77Xur8NoFtroBaCEMulfmGNUauyaNcV/KoK4/lxN53JItJaUt7OzdMU12jOdLsN985Neu2rPVIFv3eYty/rSEtTWkmIwVvVXkpFzoRTuNM+hYTPiAniHiON/h+wfNG5Ei4Lu/dGhy0NZRavF9TQTvLv/vsXQta6q+HzvF4IYsj2Dt0YBvNNL/uyO4mfA08U0jjnJCh7sjIHHrju9Q/i6r2sjNOoiynDnorUXAlUn++gkyFlksnRMLTxAKgvwYVsiQMjoOdIacp3Xwn11BaO6VsGf/9ub+P9B5XbG6gfwtVEWaag2FkWuIeFLF6qMwMAqpZFSG+lFO0iqFwxTO7MnwRTDxmiE13tfl3QHdciTc+qjtnNEPIhbJR0pQmtwZnnOmFdrxcb8phwdZOvUFA0OSXEL0VwvM6NaORpVxfotdWyZJ/JIhv1Jre0h+folgd1FIuNjZ7dVGQvbEwwVZDbsPHZNKbacHjD/sj9sK+rEll1RKTS8ReDBPWek1aoA9V80FSV6aMtI4/pVOXP6/1CBYEgB4nzZUBlzlS3uiCx9C6s4Q== orlando@hashlabs.com" >> /root/.ssh/authorized_keys

# Add ssh keys for ubuntu user (/home/ubuntu/.ssh/authorized_keys)
mkdir -p /home/ubuntu/.ssh
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDNmbm3AR92kE0igfVUJ9ZpY48oVS4Po+qH/3Jb6gF5NkHju+67Rf2MDkWQ4NzNp9yjlxL7LQk7c0dNuIR++GSS6dOLxixPXnLcYadqJF2h5qPV8RMNkOTuHR/zWPPEh77Xur8NoFtroBaCEMulfmGNUauyaNcV/KoK4/lxN53JItJaUt7OzdMU12jOdLsN985Neu2rPVIFv3eYty/rSEtTWkmIwVvVXkpFzoRTuNM+hYTPiAniHiON/h+wfNG5Ei4Lu/dGhy0NZRavF9TQTvLv/vsXQta6q+HzvF4IYsj2Dt0YBvNNL/uyO4mfA08U0jjnJCh7sjIHHrju9Q/i6r2sjNOoiynDnorUXAlUn++gkyFlksnRMLTxAKgvwYVsiQMjoOdIacp3Xwn11BaO6VsGf/9ub+P9B5XbG6gfwtVEWaag2FkWuIeFLF6qMwMAqpZFSG+lFO0iqFwxTO7MnwRTDxmiE13tfl3QHdciTc+qjtnNEPIhbJR0pQmtwZnnOmFdrxcb8phwdZOvUFA0OSXEL0VwvM6NaORpVxfotdWyZJ/JIhv1Jre0h+folgd1FIuNjZ7dVGQvbEwwVZDbsPHZNKbacHjD/sj9sK+rEll1RKTS8ReDBPWek1aoA9V80FSV6aMtI4/pVOXP6/1CBYEgB4nzZUBlzlS3uiCx9C6s4Q== orlando@hashlabs.com" >> /home/ubuntu/.ssh/authorized_keys

# Gitlab deploy key
echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCWNS3xEAIcOwBb+zQ9U6jnatul0x3dr0XM3C49bmd0U5TsDJmpEovH4C5/OFAWeeUaD9hGvC35ZcjIKkAvF7ACOTcm0Ax732DeTUGOJugLPVCYJ3Q+M7kpet0V5vDqOO7Sy72WgisU8LH+9V1L9U1WOONPq4hJj9GgTE+C7jS2m96HqOlp3cEbtU5pEPH3sH+LiVsNNzrXtWSS7T1GtxoAb/Sf+jlxETusdXy12YhhLTKCBgfpqcXg4h4IH1lSmo1OyaJwQ8heO7WJQc+TQwv/77hA16URYwhGG2jgFF+uqrgqZhvRys/CxnNECp+BkQFAt0urltd6KK+9bJhM077X" >> /home/ubuntu/.ssh/authorized_keys

# Know Hosts
ssh-keyscan -H 'gitlab.com' >> $HOME/.ssh/known_hosts
ssh-keyscan -H 'github.com' >> $HOME/.ssh/known_hosts
