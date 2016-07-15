class MiqAeBrowser
  attr_accessor :user

  # Automate Datastore Browser starting at MiqAeDomain
  #   - Starting point of searches using fqname
  #   - Searches down to the MiqAeInstances and MiqAeMethods
  #   - Returns array of objects
  #
  # Supporting options:
  #   :depth
  #          0 - starting object only
  #          1 - object + first level children
  #          2 - object + first and second level children
  #          ...
  #        nil - object + whole subtree
  #   :serialize
  #       when true, return the Hash serialized objects including fqname, domain_fqname and klass
  #       i.e.
  #         {
  #           "fqname": "/ManageIQ/System/Request",
  #           "domain_fqname": "/System/Request",       # fqname relative to /domain
  #           "klass": "MiqAeClass",
  #           "id": 75,
  #           "description": "Automation Requests",
  #           "name": "Request",
  #           "created_on": "2015-12-09T20:56:44Z",
  #           "updated_on": "2015-12-09T20:56:44Z",
  #           "namespace_id": 41,
  #           "updated_by": "system"
  #         }
  #   :state_machines
  #       when true, only objects belonging to a sub-tree that includes
  #       state machine entrypoints are returned.
  #

  def initialize(user = User.current_user)
    raise "Must be authenticated before using #{self.class.name}" unless user
    @user = user
    @waypoint_ids = MiqAeClass.waypoint_ids_for_state_machines
  end

  def domains(options = {})
    filter_ae_objects(@user.current_tenant.visible_domains, options)
  end

  def search(object_ref = nil, options = {})
    object = object_ref
    if object_ref.kind_of?(String)
      if object_ref.blank? || object_ref == "/"
        object = nil
      else
        object = find_base_object(object_ref, options)
        raise "Invalid Automate object path #{object_ref} specified to search" if object.blank?
      end
    end
    depth = options[:depth]
    options[:serialize] ? search_ae_model_serialize(object, depth, options) : search_ae_model(object, depth, options)
  end

  private

  def search_ae_model_serialize(object, depth, options = {})
    search_ae_model(object, depth, options).collect { |obj| serialize(obj) }
  end

  def search_ae_model(object, depth, options = {})
    if object
      search_object(object, depth, options)
    else
      search_domains(depth, options)
    end.flatten
  end

  def search_object(object, depth, options)
    case depth
    when -1 then []
    when 0 then Array(object)
    else
      Array(object) + children(object, options).collect do |child|
                        search_ae_model(child, depth.nil? ? nil : depth - 1, options)
                      end
    end
  end

  def search_domains(depth, options)
    case depth
    when -1 then []
    when 0 then []
    else domains(options).collect { |domain| search_ae_model(domain, depth.nil? ? nil : depth - 1, options) }
    end
  end

  def serialize(object)
    fqname = object.fqname
    domain_fqname = fqname[1..-1].sub(%r{^[^/]+}, '')
    domain_fqname = "/" if domain_fqname.blank?
    object.attributes.reverse_merge("fqname" => fqname, "domain_fqname" => domain_fqname, "klass" => object.class.name)
  end

  def find_base_object(path, options)
    parts = path.split('/').select { |p| p != "" }
    object = find_domain(parts[0], options)
    parts[1..-1].each { |part| object = children(object, options).find { |obj| part.casecmp(obj.name) == 0 } }
    object
  end

  def find_domain(domain_name, options)
    domain = domains(options).find { |d| domain_name.casecmp(d.name) == 0 }
    raise "Invalid Automate Domain #{domain_name} specified" if domain.blank?
    domain
  end

  def children(object, options = {})
    return [] unless object
    filter_ae_objects(Array(object.try(:ae_namespaces)) +
                      Array(object.try(:ae_classes)) +
                      Array(object.try(:ae_instances)) +
                      Array(object.try(:ae_methods)), options)
  end

  def filter_ae_objects(objects, options)
    return objects unless options[:state_machines]
    objects.select do |obj|
      klass_name = obj.class.name
      if klass_name == "MiqAeInstance"
        true
      else
        prefix = klass_name == "MiqAeDomain" ? "MiqAeNamespace" : klass_name
        @waypoint_ids.include?("#{prefix}::#{obj.id}")
      end
    end
  end
end
