require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')

describe Compile do
  describe "new_from_request" do
    before(:each) do
      @user = User.create!
    end

    describe "with valid request" do
      it "should load the information about the compile" do
        @compile = Compile.new_from_request(<<-EOS
          <compile>
            <token>#{@user.token}</token>
            <name>MyProject</name>
            <options>
              <compiler>latex</compiler>
              <output-format>ps</output-format>
            </options>
            <resources root-resource-path="chapters/main.tex">
              <resource path="chapters/main.tex" modified="2009-03-29T06:00Z">Hello TeX.</resource>
              <resource path="chapters/chapter1.tex" modified="2009-03-29" url="http://www.latexlab.org/getfile/bsoares/23234543543"/>
            </resources>
          </compile>
        EOS
        )

        @compile.user.should eql @user
        @compile.project.name.should eql 'MyProject'
        @compile.project.user.should eql @user
        @compile.project.unique_id.should_not be_blank
        @compile.root_resource_path.should eql 'chapters/main.tex'
        @compile.compiler.should eql 'latex'
        @compile.output_format.should eql 'ps'
 
        @compile.resources[0].should be_a(Resource)
        @compile.resources[0].path.should eql 'chapters/main.tex'
        @compile.resources[0].modified_date.should eql DateTime.parse('2009-03-29T06:00Z')
        @compile.resources[0].content.should eql 'Hello TeX.'
 
        @compile.resources[1].should be_a(Resource)
        @compile.resources[1].path.should eql 'chapters/chapter1.tex'
        @compile.resources[1].modified_date.should eql DateTime.parse('2009-03-29')
        @compile.resources[1].url.should eql 'http://www.latexlab.org/getfile/bsoares/23234543543'
      end

      it "should create a project with a random name if none is supplied" do
        @compile = Compile.new_from_request(<<-EOS
          <compile>
            <token>#{@user.token}</token>
            <resources></resources>
          </compile>
        EOS
        )

        @compile.project.name.should_not be_blank
      end

      it "should find an existing project if the name is already in use by the user" do
        @project = Project.create!(:name => 'Existing Project', :user => @user)
        @compile = Compile.new_from_request(<<-EOS
          <compile>
            <token>#{@user.token}</token>
            <name>Existing Project</name>
            <resources></resources>
          </compile>
        EOS
        )
        @compile.project.should eql(@project)
      end

      it "should create a new project if the name is already in use but by a different user" do
        @another_user = User.create!
        @project = Project.create!(:name => 'Existing Project', :user => @another_user)
        @compile = Compile.new_from_request(<<-EOS
          <compile>
            <token>#{@user.token}</token>
            <name>Existing Project</name>
            <resources></resources>
          </compile>
        EOS
        )
        @compile.project.should_not eql(@project)
      end
    end

    describe "with invalid token" do
      it "should raise a CLSI::InvalidToken error" do
        lambda{
          @compile = Compile.new_from_request(<<-EOS
            <compile>
              <token>#{Digest::MD5.hexdigest('blah')}</token>
              <resources></resources>
            </compile>
          EOS
          )
        }.should raise_error(CLSI::InvalidToken, 'user does not exist')
      end
    end
    
    describe "with an unknown compiler" do
      it "should raise a CLSI::UnknownCompiler error" do
        lambda{
          @compile = Compile.new_from_request(<<-EOS
            <compile>
              <token>#{@user.token}</token>
              <options>
                <compiler>gcc</compiler>
              </options>
              <resources></resources>
            </compile>
          EOS
          )
        }.should raise_error(CLSI::UnknownCompiler, 'gcc is not a valid compiler')
      end
    end

    describe "with an impossible output format" do
      it "should raise a CLSI::ImpossibleOutputFormat error" do
        lambda{
          @compile = Compile.new_from_request(<<-EOS
            <compile>
              <token>#{@user.token}</token>
              <options>
                <compiler>pdflatex</compiler>
                <output-format>dvi</output-format>
              </options>
              <resources></resources>
            </compile>
          EOS
          )
        }.should raise_error(CLSI::ImpossibleOutputFormat, 'pdflatex cannot produce dvi output')
      end
    end
  end

  describe "successful compile" do
    before(:all) do
      @compile = Compile.new
      @user = User.create!
      @project = Project.create!(:name => 'Test Project', :user => @user)
      @compile.user = @user
      @compile.project = @project
      @compile.root_resource_path = 'main.tex'
      @compile.resources = []
      @compile.resources << Resource.new(
        'main.tex', nil,
        '\\documentclass{article} \\begin{document} \\input{chapters/chapter1} \\end{document}', nil,
        @project,
        @user
      )
      @compile.resources << Resource.new(
        'chapters/chapter1.tex', nil,
        'Chapter1 Content!', nil,
        @project,
        @user
      )
    end
    
    shared_examples_for 'an output format of pdf' do
      it "should return the PDF for access by the client" do
        rel_pdf_path = File.join('output', @project.unique_id, 'output.pdf')
        @compile.return_files.should include(rel_pdf_path)
        File.exist?(File.join(SERVER_ROOT_DIR, rel_pdf_path)).should be_true
      end
    end
    
    shared_examples_for 'an output format of dvi' do
      it "should return the DVI for access by the client" do
        rel_path = File.join('output', @project.unique_id, 'output.dvi')
        @compile.return_files.should include(rel_path)
        File.exist?(File.join(SERVER_ROOT_DIR, rel_path)).should be_true
      end
    end

    shared_examples_for 'an output format of ps' do
      it "should return the PostScript file for access by the client" do
        rel_path = File.join('output', @project.unique_id, 'output.ps')
        @compile.return_files.should include(rel_path)
        File.exist?(File.join(SERVER_ROOT_DIR, rel_path)).should be_true
      end
    end
    
    shared_examples_for 'a successful compile' do
      it "should return the log for access by the client" do
        rel_log_path = File.join('output', @project.unique_id, 'output.log')
        @compile.return_files.should include(rel_log_path)
        File.exist?(File.join(SERVER_ROOT_DIR, rel_log_path)).should be_true
      end
    end
    
    describe 'with pdflatex compiler and output format of pdf' do
      before do
        @compile.compile
      end
      
      it_should_behave_like 'an output format of pdf'
      it_should_behave_like 'a successful compile'
    end

    describe 'with latex compiler and output format of dvi' do
      before do
        @compile.compiler = 'latex'
        @compile.output_format = 'dvi'
        @compile.compile
      end

      it_should_behave_like 'an output format of dvi'
      it_should_behave_like 'a successful compile'
    end
    
    describe 'with latex compiled and output format of pdf' do
      before do
        @compile.compiler = 'latex'
        @compile.output_format = 'pdf'
        @compile.compile
      end

      it_should_behave_like 'an output format of pdf'
      it_should_behave_like 'a successful compile'
    end

    describe 'with latex compiled and output format of ps' do
      before do
        @compile.compiler = 'latex'
        @compile.output_format = 'ps'
        @compile.compile
      end

      it_should_behave_like 'an output format of ps'
      it_should_behave_like 'a successful compile'
    end

    after(:all) do
      FileUtils.rm_r(File.join(LATEX_COMPILE_DIR, @project.unique_id))
      FileUtils.rm_r(File.join(SERVER_ROOT_DIR, 'output', @project.unique_id))
    end
  end

  describe "unsuccessful compile" do
    before(:all) do
      @compile = Compile.new
      @user = User.create!
      @project = Project.create!(:name => 'Test Project', :user => @user)
      @compile.user = @user
      @compile.project = @project
      @compile.root_resource_path = 'main.tex'
      @compile.resources = []
      @compile.resources << Resource.new(
        'main.tex', nil,
        '\\begin{document}', nil,
        @project,
        @user
      )
      lambda {@compile.compile}.should raise_error CLSI::NoOutputProduced
    end

    it "should return the log for access by the client" do
      rel_log_path = File.join('output', @project.unique_id, 'output.log')
      @compile.return_files.should include(rel_log_path)
      File.exist?(File.join(SERVER_ROOT_DIR, rel_log_path)).should be_true
    end

    after(:all) do
      FileUtils.rm_r(File.join(LATEX_COMPILE_DIR, @project.unique_id))
      FileUtils.rm_r(File.join(SERVER_ROOT_DIR, 'output', @project.unique_id))
    end
  end

  describe "timedout compile" do
    it "should timeout" do
      @compile = Compile.new
      lambda {
        @compile.send('run_with_timeout', "sh " + File.expand_path(RAILS_ROOT + '/spec/fixtures/sleep.sh'), 0.1) 
      }.should raise_error CLSI::Timeout
      %x[ps -a -x].should_not include('/bin/sleep') # lets hope no one else has sleep running!
    end
  end
end
