# Automated Deployment Script

A production-grade Bash script for automated deployment of Dockerized applications to remote Linux servers with Nginx reverse proxy configuration.

## Features

- ✅ Complete automation from git clone to live deployment
- ✅ Comprehensive error handling with meaningful exit codes
- ✅ Timestamped logging for all operations
- ✅ Input validation for all user parameters
- ✅ Idempotent execution (safe to re-run)
- ✅ SSH connectivity verification
- ✅ Automatic Docker & Nginx installation
- ✅ Container health validation
- ✅ Reverse proxy configuration
- ✅ Cleanup mode for resource removal
- ✅ POSIX-compliant code

## Prerequisites

### Local Machine
- Bash 4.0 or higher
- Git
- SSH client
- rsync

### Remote Server
- Ubuntu/Debian-based Linux distribution
- SSH access with key-based authentication
- Sudo privileges for the SSH user
- Open ports: 80 (HTTP), 22 (SSH), and your application port

## Installation

1. Clone or download the script:
```bash
wget https://github.com/Tjoseph-O/deployment-file
chmod +x deploy.sh
```

2. Ensure you have:
   - A Git repository with a Dockerfile or docker-compose.yml
   - A Personal Access Token (PAT) for Git authentication
   - SSH key for remote server access

## Usage

### Standard Deployment

Run the script and follow the interactive prompts:

```bash
./deploy.sh
```

You'll be prompted for:
- **Git Repository URL**: https://github.com/Tjoseph-O/deployment-file.git
- **Personal Access Token**: Your GitHub/GitLab PAT
- **Branch name**: `main` (default) or any branch
- **SSH username**: `ubuntu`, `root`, etc.
- **Server IP**: `192.168.1.100`
- **SSH key path**: `~/.ssh/id_rsa`
- **Application port**: `3000`, `8080`, etc.

### Cleanup Mode

To remove all deployed resources:

```bash
./deploy.sh --cleanup
```

## Script Workflow

The deployment process follows these steps:

1. **Input Collection** - Validates all user inputs
2. **Repository Cloning** - Clones or updates the Git repository
3. **Project Verification** - Ensures Dockerfile exists
4. **SSH Testing** - Verifies remote server connectivity
5. **Environment Setup** - Installs Docker, Docker Compose, and Nginx
6. **Application Deployment** - Builds and runs containers
7. **Nginx Configuration** - Sets up reverse proxy
8. **Validation** - Confirms successful deployment

## Example Session

```bash
$ ./deploy.sh

[INFO] === Step 1: Collecting User Input ===
Enter Git Repository URL: https://github.com/myuser/myapp.git
Enter Personal Access Token (PAT): ****
Enter branch name (default: main): develop
Enter SSH username: ubuntu
Enter server IP address: 192.168.1.50
Enter SSH key path: ~/.ssh/mykey.pem
Enter application port: 3000

[SUCCESS] Input collection completed
[INFO] Project: myapp | Branch: develop | Port: 3000

[INFO] === Step 2: Cloning Repository ===
[INFO] Cloning repository...
[SUCCESS] Repository cloned/updated successfully

...

[SUCCESS] ==========================================
[SUCCESS]   Deployment Completed Successfully!
[SUCCESS] ==========================================
[INFO] Application URL: http://192.168.1.50
[INFO] Container Port: 3000
[INFO] Log file: deploy_20241020_143052.log
```

## Configuration Details

### Nginx Reverse Proxy

The script automatically creates an Nginx configuration that:
- Listens on port 80
- Forwards traffic to your container port
- Includes WebSocket support
- Sets proper proxy headers

Configuration file location: `/etc/nginx/sites-available/[PROJECT_NAME]`

### Docker Setup

The script supports two deployment methods:
- **docker-compose**: If `docker-compose.yml` exists
- **Dockerfile**: Direct build and run if only Dockerfile exists

## Logging

All operations are logged to timestamped files:
- Format: `deploy_YYYYMMDD_HHMMSS.log`
- Includes: INFO, SUCCESS, WARNING, and ERROR messages
- Location: Current working directory

## Exit Codes

| Code | Description |
|------|-------------|
| 0 | Success |
| 1 | Invalid input |
| 2 | Clone/Git operation failed |
| 3 | SSH connection failed |
| 4 | Docker operation failed |
| 5 | Nginx configuration failed |
| 6 | Validation failed |

## Security Considerations

1. **PAT Handling**: Token is read securely with `-s` flag (no echo)
2. **SSH Keys**: Automatically sets proper permissions (600)
3. **StrictHostKeyChecking**: Disabled for automation (consider enabling in production)
4. **Sudo Access**: Required for Docker and Nginx operations

## Troubleshooting

### SSH Connection Failed
- Verify SSH key has correct permissions: `chmod 600 ~/.ssh/your-key`
- Test manual SSH: `ssh -i ~/.ssh/your-key user@ip`
- Check server firewall rules

### Docker Container Not Starting
- Check logs: View `deploy_*.log` file
- SSH to server and run: `docker logs [container-name]`
- Verify port availability: `sudo netstat -tlnp | grep [port]`

### Nginx 502 Bad Gateway
- Ensure container is running: `docker ps`
- Check if app is listening on the correct port
- Review Nginx logs: `sudo tail -f /var/log/nginx/error.log`

### Port Already in Use
- The script stops existing containers before deployment
- Manually stop conflicting services: `sudo systemctl stop [service]`

## Idempotency

The script is designed to be safely re-run:
- Stops and removes old containers before deploying
- Updates existing repository instead of failing
- Overwrites Nginx configuration files
- Prevents duplicate Docker networks

## Advanced Usage

### Custom Docker Compose Files

If your project uses a non-standard docker-compose filename:
```bash
# Modify line in script or rename file to docker-compose.yml
mv docker-compose.prod.yml docker-compose.yml
```

### Multi-Port Applications

For apps exposing multiple ports, modify the Nginx configuration section or add manual port mappings in your docker-compose.yml.

### SSL/TLS Support

To add SSL support:
1. Install Certbot on remote server
2. Run: `sudo certbot --nginx -d yourdomain.com`
3. Or use the generated configuration as a starting point

## Contributing

Contributions are welcome! Please ensure:
- Code follows existing style
- New features include error handling
- Logging is comprehensive
- Script remains idempotent

## License

MIT License - Feel free to use and modify for your needs.

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review the log file for detailed error messages
3. Open an issue on GitHub

## Changelog

### Version 1.0.0
- Initial release
- Complete deployment automation
- Nginx reverse proxy setup
- Comprehensive validation
- Cleanup mode support

---

**Author**: DevOps Team  
**Last Updated**: October 2024  
**Status**: Production Ready# deployment-file
