#
# Author:: Adam Jacob (<adam@opscode.com>)
# Copyright:: Copyright (c) 2008 OpsCode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require File.join(File.dirname(__FILE__), "file")
require 'uri'
require 'tempfile'
require 'net/https'

class Chef
  class Provider
    class RemoteFile < Chef::Provider::File
      
      def action_create        
        Chef::Log.debug("Checking #{@new_resource} for changes")
        do_remote_file(@new_resource.source, @current_resource.path)
      end
      
      def action_create_if_missing
        if ::File.exists?(@new_resource.path)
          Chef::Log.debug("File #{@new_resource.path} exists, taking no action.")
        else
          action_create
        end
      end
    
      def do_remote_file(source, path)
        raw_file = nil
        current_checksum = nil
        current_checksum = self.checksum(path) if ::File.exists?(path)
        if Chef::Config[:solo]
          filename = ::File.join(Chef::Config[:cookbook_path], @new_resource.cookbook_name.to_s, "files/default/#{source}")
          Chef::Log.debug("using local file for  remote_file:#{filename}")
          raw_file = ::File.open(filename)
        else
          r = Chef::REST.new(Chef::Config[:remotefile_url])
          
          url = generate_url(
            source, 
            "files", 
            { 
              :checksum => current_checksum
            }
          )
          
          
          begin
            raw_file = r.get_rest(url, true)
          rescue Net::HTTPRetriableError => e
            if e.response.kind_of?(Net::HTTPNotModified)
              Chef::Log.debug("File #{path} is unchanged")
              return false
            else
              raise e
            end
          end
        end
        
        raw_file_checksum = self.checksum(raw_file.path)
        
        if ::File.exists?(path)
          Chef::Log.debug("#{path} changed from #{current_checksum} to #{raw_file_checksum}")
          Chef::Log.info("Updating file for #{@new_resource} at #{path}")
        else
          Chef::Log.info("Creating file for #{@new_resource} at #{path}")
        end
        
        
        update = false
      
        if ::File.exists?(@new_resource.path)
          @new_resource.checksum(self.checksum(raw_file.path))
          if @new_resource.checksum != @current_resource.checksum
            Chef::Log.debug("#{@new_resource} changed from #{@current_resource.checksum} to #{@new_resource.checksum}")
            Chef::Log.info("Updating #{@new_resource} at #{@new_resource.path}")
            update = true
          end
        else
          Chef::Log.info("Creating #{@new_resource} at #{@new_resource.path}")
          update = true
        end
      
        
        if update
          backup(path)
          FileUtils.cp(raw_file.path, path)
          @new_resource.updated = true
        else
          Chef::Log.debug("#{@new_resource} is unchanged")
        end
        

        set_owner if @new_resource.owner != nil
        set_group if @new_resource.group != nil
        set_mode if @new_resource.mode != nil
        return true
      end
      
    end
  end
end